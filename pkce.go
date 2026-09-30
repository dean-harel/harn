package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const openRouterBase = "https://openrouter.ai"

// pkceVerifier is 48 random bytes as 64 base64url characters (RFC 7636 allows 43 to 128).
func pkceVerifier() (string, error) {
	b := make([]byte, 48)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func authURL(challenge, label, workspace string) string {
	q := url.Values{}
	q.Set("code_challenge", challenge)
	q.Set("code_challenge_method", "S256")
	q.Set("key_label", label)
	if workspace != "" {
		q.Set("required_workspace_id", workspace)
	}
	return openRouterBase + "/auth?" + q.Encode()
}

func exchangeCode(base, code, verifier string) (string, error) {
	body, err := json.Marshal(map[string]string{"code": code, "code_verifier": verifier, "code_challenge_method": "S256"})
	if err != nil {
		return "", err
	}
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Post(base+"/api/v1/auth/keys", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", err
	}
	var r struct {
		Key   string          `json:"key"`
		Error json.RawMessage `json:"error"`
	}
	if json.Unmarshal(raw, &r) == nil && r.Key != "" {
		return r.Key, nil
	}
	return "", errors.New(apiError(raw, r.Error))
}

// apiError reads OpenRouter's error message, falling back to the raw body.
func apiError(raw []byte, e json.RawMessage) string {
	var obj struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(e, &obj) == nil && obj.Message != "" {
		return obj.Message
	}
	var s string
	if json.Unmarshal(e, &s) == nil && s != "" {
		return s
	}
	if len(e) == 0 && json.Valid(raw) {
		return "no error message"
	}
	return strings.TrimSpace(string(raw))
}

// cliError carries the exit code and hints for a failure the caller reports through die.
type cliError struct {
	code  int
	msg   string
	hints []string
}

func (e *cliError) Error() string { return e.msg }

func loginPKCE(name string, args []string, workspace string) {
	open := openBrowser
	for _, a := range args {
		if a != "--no-open" {
			die(2, "unknown flag: "+a, fmt.Sprintf("usage: harn login %s [--no-open]", name))
		}
		open = nil
	}
	path, err := pkceLogin(os.Stdin, os.Stderr, openRouterBase, name, workspace, open)
	var ce *cliError
	if errors.As(err, &ce) {
		die(ce.code, ce.msg, ce.hints...)
	}
	fmt.Fprintf(os.Stderr, "harn: stored the key for %s in %s\n", name, path)
}

// pkceLogin prints the URL, reads the code from in, exchanges it at base and stores the key.
func pkceLogin(in io.Reader, out io.Writer, base, name, workspace string, open func(string)) (string, error) {
	verifier, err := pkceVerifier()
	if err != nil {
		return "", &cliError{3, "cannot generate a PKCE verifier", []string{err.Error()}}
	}
	u := authURL(pkceChallenge(verifier), "harn-"+shortHostname(), workspace)
	fmt.Fprintf(out, "Open this URL, approve, then paste the code it shows:\n  %s\n", u)
	if open != nil {
		open(u)
	}
	fmt.Fprint(out, "Code: ")
	code, _ := readLine(in)
	if code = strings.TrimSpace(code); code == "" {
		return "", &cliError{2, "no code entered", nil}
	}
	key, err := exchangeCode(base, code, verifier)
	if err != nil {
		return "", &cliError{2, "OpenRouter returned no key", []string{err.Error()}}
	}
	path, err := storeWrite(name, key)
	if err != nil {
		return "", &cliError{3, "cannot write " + path, []string{err.Error()}}
	}
	return path, nil
}

func shortHostname() string {
	h, err := os.Hostname()
	if err != nil || h == "" {
		return "unknown"
	}
	h, _, _ = strings.Cut(h, ".")
	return h
}

func openBrowser(u string) {
	cmd := "xdg-open"
	if runtime.GOOS == "darwin" {
		cmd = "open"
	}
	if path, err := exec.LookPath(cmd); err == nil {
		_ = exec.Command(path, u).Run()
	}
}
