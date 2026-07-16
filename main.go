package main

import (
	"bytes"
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

var db *sql.DB

var (
	AES_SECRET_KEY []byte
	SECRET_SALT    string
	APP_VERSION    string
	privKey        *rsa.PrivateKey // Cached at startup — never read from disk per-request
)

func initConfig() {
	AES_SECRET_KEY = []byte(strings.TrimSpace(os.Getenv("AES_SECRET_KEY")))
	if len(AES_SECRET_KEY) == 0 {
		log.Fatal("[FATAL] AES_SECRET_KEY env var is not set. Refusing to start.")
	}

	SECRET_SALT = strings.TrimSpace(os.Getenv("HMAC_SECRET_SALT"))
	if SECRET_SALT == "" {
		log.Fatal("[FATAL] HMAC_SECRET_SALT env var is not set. Refusing to start.")
	}

	APP_VERSION = strings.TrimSpace(os.Getenv("APP_VERSION"))
	if APP_VERSION == "" {
		log.Fatal("[FATAL] APP_VERSION env var is not set. Refusing to start.")
	}

	if os.Getenv("ADMIN_PASS") == "" {
		log.Fatal("[FATAL] ADMIN_PASS env var is not set. Refusing to start.")
	}

	defaultProductID = normalizeProductID(os.Getenv("DEFAULT_PRODUCT_ID"))

	licenseKeyPrefix = strings.TrimSpace(os.Getenv("LICENSE_KEY_PREFIX"))
	if licenseKeyPrefix == "" {
		log.Fatal("[FATAL] LICENSE_KEY_PREFIX env var is not set. Refusing to start.")
	}

	// Load and cache RSA private key once at startup
	privData, err := os.ReadFile("private.pem")
	if err != nil {
		log.Fatal("[FATAL] Cannot read private.pem: ", err)
	}
	block, _ := pem.Decode(privData)
	if block == nil {
		log.Fatal("[FATAL] private.pem is not a valid PEM block.")
	}
	privKey, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		log.Fatal("[FATAL] Cannot parse private.pem: ", err)
	}
	log.Println("[OK] RSA private key loaded and cached.")
}

func encryptPayloadAES(plaintext string) (string, error) {
	c, err := aes.NewCipher(AES_SECRET_KEY)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(c)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(gcm.Seal(nonce, nonce, []byte(plaintext), nil)), nil
}

func sendDiscordWebhook(msg string) {
	webhookUrl := os.Getenv("DISCORD_WEBHOOK")
	if webhookUrl == "" {
		return
	}
	payload := map[string]string{"content": msg}
	jsonPayload, _ := json.Marshal(payload)
	resp, err := http.Post(webhookUrl, "application/json", bytes.NewBuffer(jsonPayload))
	if err != nil {
		log.Println("[Discord] Webhook send failed:", err)
		return
	}
	resp.Body.Close()
}

// nowStr returns current time formatted in UTC+7.
func nowStr() string {
	return time.Now().UTC().Add(7 * time.Hour).Format("2006-01-02 15:04:05 (UTC+7)")
}

// truncHWID shows first 8 + last 4 chars of HWID for privacy.
func truncHWID(h string) string {
	if h == "" || h == "0" {
		return "(unbound)"
	}
	if len(h) <= 16 {
		return h
	}
	return h[:8] + "..." + h[len(h)-4:]
}

// clientAuthDenied is returned to clients for any license/HWID/expiry failure (no oracle).
const clientAuthDenied = "ERROR 0xAUTH: License verification failed."

// expireStr formats an expiry timestamp into a human-readable string.
func expireStr(ts int64) string {
	if ts == 0 {
		return "Never (Lifetime)"
	}
	t := time.Unix(ts, 0)
	days := int(time.Until(t).Hours() / 24)
	if days < 0 {
		return fmt.Sprintf("EXPIRED — %s (%d days ago)", t.Format("2006-01-02"), -days)
	}
	return fmt.Sprintf("%s (%d days remaining)", t.Format("2006-01-02"), days)
}

// getIP extracts the real client IP (without port).
// Only trusts X-Forwarded-For when the direct connection comes from localhost (nginx proxy).
func getIP(r *http.Request) string {
	remoteIP := r.RemoteAddr
	host := remoteIP
	if h, _, err := net.SplitHostPort(remoteIP); err == nil {
		host = h
	}
	if host == "127.0.0.1" || host == "::1" {
		if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
			return strings.TrimSpace(strings.SplitN(forwarded, ",", 2)[0])
		}
	}
	return host
}

func rateLimitMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Bot/admin API calls share one egress IP; skip limit for authenticated admin.
		if adminAuth(r) {
			next(w, r)
			return
		}

		ip := getIP(r)

		var lastSeen int64
		err := db.QueryRow("SELECT last_seen FROM rate_limits WHERE ip = ?", ip).Scan(&lastSeen)

		now := time.Now().Unix()
		if err == nil && (now-lastSeen) < 2 {
			http.Error(w, "ERROR 0xRATE: Too many requests. Please slow down.", http.StatusTooManyRequests)
			return
		}

		db.Exec(`INSERT INTO rate_limits (ip, last_seen) VALUES (?, ?)
		         ON CONFLICT(ip) DO UPDATE SET last_seen=excluded.last_seen;`, ip, now)

		next(w, r)
	}
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "./db/licenses.db")
	if err != nil {
		log.Fatal("Could not open SQLite database: ", err)
	}

	db.SetMaxOpenConns(1)
	db.Exec("PRAGMA journal_mode=WAL;")
	db.Exec("PRAGMA busy_timeout=5000;")

	createTableQuery := `
    CREATE TABLE IF NOT EXISTS licenses_v2 (
        key TEXT PRIMARY KEY,
        hwid TEXT,
        expire_ts INTEGER DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS rate_limits (
        ip TEXT PRIMARY KEY,
        last_seen INTEGER
    );
    CREATE TABLE IF NOT EXISTS used_nonces (
        nonce TEXT PRIMARY KEY,
        used_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_nonces_used_at ON used_nonces(used_at);`
	_, err = db.Exec(createTableQuery)
	if err != nil {
		log.Fatal("Could not create table: ", err)
	}

	// Data Migration: copy old keys to new schema if migrating from legacy table
	db.Exec(`INSERT OR IGNORE INTO licenses_v2 (key, hwid, expire_ts) SELECT key, hwid, 0 FROM licenses;`)

	// Multi-product: product_id on each license
	if _, err := db.Exec(`ALTER TABLE licenses_v2 ADD COLUMN product_id TEXT NOT NULL DEFAULT ''`); err != nil {
		if !strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			log.Println("[DB] product_id migration:", err)
		}
	}
}

var productIDRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,31}$`)

var defaultProductID string
var licenseKeyPrefix string

func normalizeProductID(id string) string {
	id = strings.ToLower(strings.TrimSpace(id))
	if id == "" {
		return defaultProductID
	}
	if !productIDRe.MatchString(id) {
		return ""
	}
	return id
}

type ahkCacheEntry struct {
	payload string
	mtime   time.Time
}

const (
	deliveryScript  = "script"
	deliveryFile    = "file"
	deliveryKeyOnly = "key_only"
)

type licenseProductMeta struct {
	Delivery string `json:"delivery"`
}

type licenseCatalogEntry struct {
	Delivery string `json:"delivery"`
}

var (
	ahkPayloadMu sync.RWMutex
	ahkPayloads  = map[string]ahkCacheEntry{}

	licenseCatalogMu sync.RWMutex
	licenseCatalog   map[string]licenseCatalogEntry
	licenseCatalogAt time.Time
)

func normalizeDeliveryMode(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "key_only", "keyonly", "key-only":
		return deliveryKeyOnly
	case "file", "binary", "payload":
		return deliveryFile
	default:
		return deliveryScript
	}
}

func loadLicenseCatalog() {
	path := filepath.Join("config", "license-products.json")
	info, err := os.Stat(path)
	if err != nil {
		licenseCatalogMu.Lock()
		licenseCatalog = map[string]licenseCatalogEntry{}
		licenseCatalogMu.Unlock()
		return
	}
	if !licenseCatalogAt.IsZero() && !info.ModTime().After(licenseCatalogAt) {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var parsed map[string]licenseCatalogEntry
	if err := json.Unmarshal(data, &parsed); err != nil {
		log.Printf("Error parsing %s: %v", path, err)
		return
	}
	licenseCatalogMu.Lock()
	licenseCatalog = parsed
	licenseCatalogAt = info.ModTime()
	licenseCatalogMu.Unlock()
}

func readProductMeta(productID string) (licenseProductMeta, bool) {
	path := filepath.Join("products", productID, "meta.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return licenseProductMeta{}, false
	}
	var meta licenseProductMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		log.Printf("Error parsing %s: %v", path, err)
		return licenseProductMeta{}, false
	}
	return meta, true
}

func productDeliveryMode(productID string) string {
	productID = normalizeProductID(productID)
	if productID == "" {
		return deliveryScript
	}
	if meta, ok := readProductMeta(productID); ok && strings.TrimSpace(meta.Delivery) != "" {
		return normalizeDeliveryMode(meta.Delivery)
	}
	loadLicenseCatalog()
	licenseCatalogMu.RLock()
	entry, ok := licenseCatalog[productID]
	licenseCatalogMu.RUnlock()
	if ok && strings.TrimSpace(entry.Delivery) != "" {
		return normalizeDeliveryMode(entry.Delivery)
	}
	if productPayloadFileReady(productID, "payload.ahk") {
		return deliveryScript
	}
	if productPayloadFileReady(productID, "payload.bin") {
		return deliveryFile
	}
	return deliveryScript
}

func productPayloadFileReady(productID, filename string) bool {
	productID = normalizeProductID(productID)
	if productID == "" || filename == "" {
		return false
	}
	path := filepath.Join("products", productID, filename)
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func productRegistered(productID string) bool {
	productID = normalizeProductID(productID)
	if productID == "" {
		return false
	}
	if _, ok := readProductMeta(productID); ok {
		return true
	}
	loadLicenseCatalog()
	licenseCatalogMu.RLock()
	_, ok := licenseCatalog[productID]
	licenseCatalogMu.RUnlock()
	if ok {
		return true
	}
	dir := filepath.Join("products", productID)
	st, err := os.Stat(dir)
	return err == nil && st.IsDir()
}

// productPayloadPath — per-product script: products/<productId>/payload.ahk
func productPayloadPath(productID string) string {
	productID = normalizeProductID(productID)
	if productID == "" {
		productID = defaultProductID
	}
	if productID == "" {
		return ""
	}
	return filepath.Join("products", productID, "payload.ahk")
}

func productPayloadReady(productID string) bool {
	productID = normalizeProductID(productID)
	if productID == "" {
		return false
	}
	switch productDeliveryMode(productID) {
	case deliveryKeyOnly:
		return productRegistered(productID)
	case deliveryFile:
		return productPayloadFileReady(productID, "payload.bin")
	default:
		return productPayloadFileReady(productID, "payload.ahk")
	}
}

func payloadNotReadyMessage(productID string) string {
	switch productDeliveryMode(productID) {
	case deliveryKeyOnly:
		return fmt.Sprintf("Product not registered (need products/%s/meta.json or config/license-products.json)", productID)
	case deliveryFile:
		return fmt.Sprintf("Product payload not deployed (need products/%s/payload.bin)", productID)
	default:
		return fmt.Sprintf("Product payload not deployed (run scripts/sync-product-payloads.sh — need products/%s/payload.ahk)", productID)
	}
}

func loadAhkPayload(productID string) {
	productID = normalizeProductID(productID)
	if productID == "" {
		productID = defaultProductID
	}
	path := productPayloadPath(productID)
	info, err := os.Stat(path)
	if err != nil {
		log.Printf("Error stat %s (product=%s): %v", path, productID, err)
		return
	}
	ahkPayloadMu.Lock()
	defer ahkPayloadMu.Unlock()
	if cached, ok := ahkPayloads[productID]; ok && !info.ModTime().After(cached.mtime) {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		log.Printf("Error reading %s (product=%s): %v", path, productID, err)
		return
	}
	ahkPayloads[productID] = ahkCacheEntry{payload: string(data), mtime: info.ModTime()}
}

func getProductPayload(productID string) string {
	productID = normalizeProductID(productID)
	if productID == "" {
		productID = defaultProductID
	}
	switch productDeliveryMode(productID) {
	case deliveryKeyOnly:
		return ""
	case deliveryFile:
		return readPayloadFile(productID, "payload.bin")
	default:
		return getAhkPayload(productID)
	}
}

func readPayloadFile(productID, filename string) string {
	path := filepath.Join("products", productID, filename)
	data, err := os.ReadFile(path)
	if err != nil {
		log.Printf("Error reading %s (product=%s): %v", path, productID, err)
		return ""
	}
	return string(data)
}

func getAhkPayload(productID string) string {
	productID = normalizeProductID(productID)
	if productID == "" {
		productID = defaultProductID
	}
	loadAhkPayload(productID)
	ahkPayloadMu.RLock()
	defer ahkPayloadMu.RUnlock()
	if cached, ok := ahkPayloads[productID]; ok && cached.payload != "" {
		return cached.payload
	}
	return "MsgBox, Error locating product payload script. Please inform the developer!\n"
}

type AuthRequest struct {
	HWID    string `json:"hwid"`
	Key     string `json:"key"`
	Nonce   string `json:"nonce"`
	Sig     string `json:"sig"`
	Version string `json:"version"`
}

type AuthResponse struct {
	Signature    []byte `json:"signature"`
	Payload      string `json:"payload"`
	DeliveryMode string `json:"delivery_mode,omitempty"`
}

// verifyHMAC checks HMAC-SHA256 signature for a request.
func verifyHMAC(hwid, key, nonce, sig string) bool {
	mac := hmac.New(sha256.New, []byte(SECRET_SALT))
	mac.Write([]byte(fmt.Sprintf("%s:%s:%s", hwid, key, nonce)))
	expected := fmt.Sprintf("%x", mac.Sum(nil))
	return hmac.Equal([]byte(sig), []byte(expected))
}

// adminAuth checks the Authorization header against ADMIN_PASS env var.
// Uses constant-time comparison to prevent timing attacks.
func adminAuth(r *http.Request) bool {
	provided := r.Header.Get("Authorization")
	expected := os.Getenv("ADMIN_PASS")
	return hmac.Equal([]byte(provided), []byte(expected))
}

func authEndpoint(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	// 0. Version gate
	log.Printf("Incoming version: %q, Expected: %q", req.Version, APP_VERSION)
	if req.Version != APP_VERSION {
		ip := getIP(r)
		go sendDiscordWebhook(fmt.Sprintf(
			"**[OUTDATED CLIENT]**\n```\nKey     : %s\nIP      : %s\nSent    : %s\nRequired: %s\nTime    : %s\n```",
			req.Key, ip, req.Version, APP_VERSION, nowStr(),
		))
		http.Error(w, "ERROR 0xVER: Please download the latest version from our website.", http.StatusUpgradeRequired)
		return
	}

	// 1. HMAC verification — no secrets logged on failure
	if !verifyHMAC(req.HWID, req.Key, req.Nonce, req.Sig) {
		ip := getIP(r)
		log.Printf("[SECURITY] HMAC validation failed. IP: %s, Key: %s", ip, req.Key)
		go sendDiscordWebhook(fmt.Sprintf(
			"**[SECURITY — INVALID SIGNATURE]**\n```\nKey    : %s\nHWID   : %s\nIP     : %s\nVersion: %s\nTime   : %s\n```",
			req.Key, truncHWID(req.HWID), ip, req.Version, nowStr(),
		))
		http.Error(w, "ERROR 0xSIG: Invalid Request! API Spoofing detected.", http.StatusForbidden)
		return
	}

	// 2. License & HWID validation (before nonce — failed attempts do not burn nonces)
	var existingHWID string
	var expireTS int64
	var productID string
	err := db.QueryRow(
		"SELECT hwid, expire_ts, COALESCE(NULLIF(product_id, ''), ?) FROM licenses_v2 WHERE key = ?",
		defaultProductID, req.Key,
	).Scan(&existingHWID, &expireTS, &productID)

	if err == sql.ErrNoRows {
		go sendDiscordWebhook(fmt.Sprintf(
			"**[INVALID KEY ATTEMPT]**\n```\nKey : %s\nIP  : %s\nTime: %s\n```",
			req.Key, getIP(r), nowStr(),
		))
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	} else if err == nil {
		isFirstUse := existingHWID == "" || existingHWID == "0"
		if isFirstUse {
			db.Exec(`UPDATE licenses_v2 SET hwid = ? WHERE key = ?`, req.HWID, req.Key)
			existingHWID = req.HWID
			go sendDiscordWebhook(fmt.Sprintf(
				"**[KEY ACTIVATED — FIRST USE]**\n```\nKey    : %s\nHWID   : %s\nIP     : %s\nLicense: %s\nTime   : %s\n```",
				req.Key, truncHWID(req.HWID), getIP(r), expireStr(expireTS), nowStr(),
			))
		}

		if existingHWID != req.HWID {
			go sendDiscordWebhook(fmt.Sprintf(
				"**[SECURITY — HWID MISMATCH]**\n```\nKey          : %s\nBound HWID   : %s\nAttempted HWID: %s\nIP           : %s\nVersion      : %s\nLicense      : %s\nTime         : %s\n```",
				req.Key, truncHWID(existingHWID), truncHWID(req.HWID),
				getIP(r), req.Version, expireStr(expireTS), nowStr(),
			))
			http.Error(w, clientAuthDenied, http.StatusForbidden)
			return
		}

		if expireTS != 0 && time.Now().Unix() > expireTS {
			go sendDiscordWebhook(fmt.Sprintf(
				"**[LICENSE EXPIRED]**\n```\nKey    : %s\nHWID   : %s\nIP     : %s\nExpiry : %s\nTime   : %s\n```",
				req.Key, truncHWID(req.HWID), getIP(r), expireStr(expireTS), nowStr(),
			))
			http.Error(w, clientAuthDenied, http.StatusForbidden)
			return
		}
	} else {
		http.Error(w, "ERROR 0xDB: Database query failed", http.StatusInternalServerError)
		return
	}

	// 3. Nonce replay protection — only after license checks pass
	if len(req.Nonce) < 8 {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}
	if _, err := db.Exec("INSERT INTO used_nonces (nonce, used_at) VALUES (?, ?)", req.Nonce, time.Now().Unix()); err != nil {
		ip := getIP(r)
		go sendDiscordWebhook(fmt.Sprintf(
			"**[SECURITY — REPLAY ATTACK]**\n```\nKey  : %s\nIP   : %s\nNonce: %s...\nTime : %s\n```",
			req.Key, ip, req.Nonce[:8], nowStr(),
		))
		http.Error(w, "ERROR 0xREPLAY: Request already processed.", http.StatusForbidden)
		return
	}

	// 4. Encrypt and sign product payload for this license (per-product cache)
	mode := productDeliveryMode(productID)
	encryptedPayload, err := encryptPayloadAES(getProductPayload(productID))
	if err != nil {
		http.Error(w, "Payload encryption failed", http.StatusInternalServerError)
		return
	}

	payloadWithNonce := fmt.Sprintf("%s|%s", req.Nonce, encryptedPayload)
	hashed := sha256.Sum256([]byte(payloadWithNonce))
	signature, err := rsa.SignPKCS1v15(rand.Reader, privKey, crypto.SHA256, hashed[:])
	if err != nil {
		http.Error(w, "Failed to sign", http.StatusInternalServerError)
		return
	}

	go sendDiscordWebhook(fmt.Sprintf(
		"**[LOGIN SUCCESS]**\n```\nKey    : %s\nHWID   : %s\nIP     : %s\nVersion: %s\nLicense: %s\nTime   : %s\n```",
		req.Key, truncHWID(req.HWID), getIP(r), req.Version, expireStr(expireTS), nowStr(),
	))

	resp := AuthResponse{
		Signature:    signature,
		Payload:      encryptedPayload,
		DeliveryMode: mode,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func heartbeatEndpoint(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	if req.Version != APP_VERSION {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}

	if !verifyHMAC(req.HWID, req.Key, req.Nonce, req.Sig) {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}

	var existingHWID string
	var expireTS int64
	err := db.QueryRow("SELECT hwid, expire_ts FROM licenses_v2 WHERE key = ?", req.Key).Scan(&existingHWID, &expireTS)
	if err != nil || existingHWID != req.HWID {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}

	if expireTS != 0 && time.Now().Unix() > expireTS {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}

	if len(req.Nonce) < 8 {
		http.Error(w, clientAuthDenied, http.StatusForbidden)
		return
	}

	if _, err := db.Exec("INSERT INTO used_nonces (nonce, used_at) VALUES (?, ?)", req.Nonce, time.Now().Unix()); err != nil {
		http.Error(w, "ERROR 0xREPLAY: Request already processed.", http.StatusForbidden)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func productReadyEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}
	productID := normalizeProductID(r.URL.Query().Get("product"))
	if productID == "" {
		http.Error(w, "Invalid product parameter", http.StatusBadRequest)
		return
	}
	if productPayloadReady(productID) {
		fmt.Fprint(w, "ready")
		return
	}
	http.Error(w, "not_ready", http.StatusNotFound)
}

func createKeyEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}

	newKey := r.URL.Query().Get("key")
	if newKey == "" {
		b := make([]byte, 4)
		rand.Read(b)
		newKey = fmt.Sprintf("%s-%X-%X", licenseKeyPrefix, b[:2], b[2:])
	}

	days := 0
	if r.URL.Query().Get("days") != "" {
		fmt.Sscanf(r.URL.Query().Get("days"), "%d", &days)
	}

	expireTS := int64(0)
	if days > 0 {
		expireTS = time.Now().Add(time.Duration(days) * 24 * time.Hour).Unix()
	}

	productID := normalizeProductID(r.URL.Query().Get("product"))
	if productID == "" {
		http.Error(w, "Invalid product parameter", http.StatusBadRequest)
		return
	}
	if !productPayloadReady(productID) {
		http.Error(w, payloadNotReadyMessage(productID), http.StatusBadRequest)
		return
	}

	_, err := db.Exec(
		`INSERT INTO licenses_v2 (key, hwid, expire_ts, product_id) VALUES (?, '0', ?, ?)`,
		newKey, expireTS, productID,
	)
	if err != nil {
		http.Error(w, "Failed to create key (Maybe it already exists?)", http.StatusInternalServerError)
		return
	}

	go sendDiscordWebhook(fmt.Sprintf(
		"**[KEY CREATED]**\n```\nKey     : %s\nDuration: %s\nExpires : %s\nAdmin IP: %s\nTime    : %s\n```",
		newKey,
		func() string {
			if days == 0 {
				return "Lifetime (no expiry)"
			}
			return fmt.Sprintf("%d days", days)
		}(),
		expireStr(expireTS),
		getIP(r), nowStr(),
	))
	fmt.Fprintf(w, "Successfully created new license key: %s (Duration: %d days)\n", newKey, days)
}

func resetHwidEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}

	keyToReset := r.URL.Query().Get("key")
	if keyToReset == "" {
		http.Error(w, "Missing key parameter", http.StatusBadRequest)
		return
	}

	var prevHWID string
	err := db.QueryRow("SELECT hwid FROM licenses_v2 WHERE key = ?", keyToReset).Scan(&prevHWID)
	if err == sql.ErrNoRows {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	if prevHWID == "" || prevHWID == "0" {
		http.Error(w, "HWID_NOT_BOUND", http.StatusBadRequest)
		return
	}

	res, err := db.Exec(`UPDATE licenses_v2 SET hwid = '0' WHERE key = ?`, keyToReset)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	}
	go sendDiscordWebhook(fmt.Sprintf(
		"**[HWID RESET]**\n```\nKey          : %s\nPrevious HWID: %s\nAdmin IP     : %s\nTime         : %s\n```",
		keyToReset, truncHWID(prevHWID), getIP(r), nowStr(),
	))
	fmt.Fprintf(w, "Successfully reset HWID for key: %s\n", keyToReset)
}

func keyHwidEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}
	key := r.URL.Query().Get("key")
	if key == "" {
		http.Error(w, "Missing key parameter", http.StatusBadRequest)
		return
	}
	var hwid string
	err := db.QueryRow("SELECT hwid FROM licenses_v2 WHERE key = ?", key).Scan(&hwid)
	if err == sql.ErrNoRows {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	if hwid != "" && hwid != "0" {
		fmt.Fprint(w, "bound")
	} else {
		fmt.Fprint(w, "unbound")
	}
}

func extendKeyEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}

	keyToExtend := r.URL.Query().Get("key")
	if keyToExtend == "" {
		http.Error(w, "Missing key parameter", http.StatusBadRequest)
		return
	}

	days := 0
	if r.URL.Query().Get("days") != "" {
		fmt.Sscanf(r.URL.Query().Get("days"), "%d", &days)
	}
	if days <= 0 {
		http.Error(w, "Missing or invalid days parameter", http.StatusBadRequest)
		return
	}

	var expireTS int64
	err := db.QueryRow("SELECT expire_ts FROM licenses_v2 WHERE key = ?", keyToExtend).Scan(&expireTS)
	if err == sql.ErrNoRows {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	if expireTS == 0 {
		http.Error(w, "Cannot extend lifetime key", http.StatusBadRequest)
		return
	}

	now := time.Now().Unix()
	base := expireTS
	if base < now {
		base = now
	}
	newExpire := base + int64(days)*86400

	res, err := db.Exec(`UPDATE licenses_v2 SET expire_ts = ? WHERE key = ?`, newExpire, keyToExtend)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	}

	go sendDiscordWebhook(fmt.Sprintf(
		"**[KEY EXTENDED]**\n```\nKey     : %s\nAdded   : %d days\nExpires : %s\nAdmin IP: %s\nTime    : %s\n```",
		keyToExtend, days, expireStr(newExpire), getIP(r), nowStr(),
	))
	fmt.Fprintf(w, "Successfully extended license key: %s (New expiry ts: %d)\n", keyToExtend, newExpire)
}

func revokeKeyEndpoint(w http.ResponseWriter, r *http.Request) {
	if !adminAuth(r) {
		http.Error(w, "Unauthorized", http.StatusForbidden)
		return
	}

	keyToRevoke := r.URL.Query().Get("key")
	if keyToRevoke == "" {
		http.Error(w, "Missing key parameter", http.StatusBadRequest)
		return
	}

	res, err := db.Exec(`DELETE FROM licenses_v2 WHERE key = ?`, keyToRevoke)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		http.Error(w, "Key not found", http.StatusNotFound)
		return
	}

	go sendDiscordWebhook(fmt.Sprintf(
		"**[KEY REVOKED]**\n```\nKey     : %s\nAdmin IP: %s\nTime    : %s\n```",
		keyToRevoke, getIP(r), nowStr(),
	))
	fmt.Fprintf(w, "Successfully revoked license key: %s\n", keyToRevoke)
}

func updateEndpoint(w http.ResponseWriter, r *http.Request) {
	fileData, err := os.ReadFile("db/client.exe")
	if err != nil {
		http.Error(w, "Update file not found", http.StatusNotFound)
		return
	}
	hash := sha256.Sum256(fileData)
	hashStr := fmt.Sprintf("%x", hash)
	w.Header().Set("X-File-Hash", hashStr)
	go sendDiscordWebhook(fmt.Sprintf(
		"**[AUTO-UPDATE SERVED]**\n```\nFile  : client.exe\nSize  : %.1f KB\nSHA256: %s...\nIP    : %s\nTime  : %s\n```",
		float64(len(fileData))/1024, hashStr[:16], getIP(r), nowStr(),
	))
	http.ServeFile(w, r, "db/client.exe")
}

func main() {
	initConfig()
	initDB()
	loadAhkPayload(defaultProductID)

	// Periodically prune nonces older than 1 hour
	go func() {
		for {
			time.Sleep(10 * time.Minute)
			db.Exec("DELETE FROM used_nonces WHERE used_at < ?", time.Now().Unix()-3600)
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	go sendDiscordWebhook(fmt.Sprintf(
		"**[SERVER ONLINE]**\n```\nVersion: %s\nPort   : %s\nTime   : %s\n```",
		APP_VERSION, port, nowStr(),
	))

	http.HandleFunc("/auth", rateLimitMiddleware(authEndpoint))
	http.HandleFunc("/reset_hwid", rateLimitMiddleware(resetHwidEndpoint))
	http.HandleFunc("/key_hwid", rateLimitMiddleware(keyHwidEndpoint))
	http.HandleFunc("/create_key", rateLimitMiddleware(createKeyEndpoint))
	http.HandleFunc("/product_ready", rateLimitMiddleware(productReadyEndpoint))
	http.HandleFunc("/extend_key", rateLimitMiddleware(extendKeyEndpoint))
	http.HandleFunc("/revoke_key", rateLimitMiddleware(revokeKeyEndpoint))
	http.HandleFunc("/update", updateEndpoint)
	http.HandleFunc("/heartbeat", rateLimitMiddleware(heartbeatEndpoint))
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	log.Printf("Server listening on :%s", port)

	srv := &http.Server{
		Addr:         ":" + port,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 120 * time.Second,
	}

	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
