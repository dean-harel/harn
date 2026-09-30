package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestPKCEChallengeMatchesRFC7636AppendixB(t *testing.T) {
	got := pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
	if got != "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" {
		t.Errorf("challenge %s", got)
	}
}

func TestPKCEVerifierShape(t *testing.T) {
	v, err := pkceVerifier()
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_-]{64}$`).MatchString(v) {
		t.Errorf("verifier %q", v)
	}
}

func TestAuthURL(t *testing.T) {
	u, err := url.Parse(authURL("chal", "harn-host", ""))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if u.Scheme != "https" || u.Host != "openrouter.ai" || u.Path != "/auth" {
		t.Errorf("url %s", u)
	}
	if q.Get("code_challenge") != "chal" || q.Get("code_challenge_method") != "S256" || q.Get("key_label") != "harn-host" {
		t.Errorf("query %v", q)
	}
	if _, ok := q["required_workspace_id"]; ok {
		t.Error("no workspace pin without a workspace")
	}
}

func TestExchangeCodeReturnsKey(t *testing.T) {
	var got map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/api/v1/auth/keys" {
			t.Errorf("request %s %s", r.Method, r.URL.Path)
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("content type %q", ct)
		}
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		fmt.Fprint(w, `{"key":"sk-or-from-pkce"}`)
	}))
	defer srv.Close()
	key, err := exchangeCode(srv.URL, "the-code-123", "verifier-abc")
	if err != nil || key != "sk-or-from-pkce" {
		t.Fatalf("key %q, err %v", key, err)
	}
	if got["code"] != "the-code-123" || got["code_verifier"] != "verifier-abc" || got["code_challenge_method"] != "S256" {
		t.Errorf("body %v", got)
	}
}

func TestExchangeCodeReportsTheAPIError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprint(w, `{"error":{"message":"invalid code"}}`)
	}))
	defer srv.Close()
	if _, err := exchangeCode(srv.URL, "bad", "v"); err == nil || err.Error() != "invalid code" {
		t.Errorf("err %v", err)
	}
}

func TestExchangeCodeReportsANonJSONBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprint(w, "upstream down")
	}))
	defer srv.Close()
	if _, err := exchangeCode(srv.URL, "c", "v"); err == nil || err.Error() != "upstream down" {
		t.Errorf("err %v", err)
	}
}

func TestPKCELoginStoresTheReturnedKey(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	var body map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		fmt.Fprint(w, `{"key":"sk-or-from-pkce"}`)
	}))
	defer srv.Close()
	var out bytes.Buffer
	opened := ""
	path, err := pkceLogin(strings.NewReader("the-code-123\n"), &out, srv.URL, "openrouter", "", func(u string) { opened = u })
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(path); string(got) != "sk-or-from-pkce" {
		t.Errorf("stored %q", got)
	}
	if body["code"] != "the-code-123" {
		t.Errorf("code %q", body["code"])
	}
	if want := "code_challenge=" + pkceChallenge(body["code_verifier"]); !strings.Contains(out.String(), want) {
		t.Errorf("the printed URL lacks the challenge for the verifier sent (%s):\n%s", want, out.String())
	}
	if opened == "" || !strings.Contains(out.String(), opened) {
		t.Error("the URL opened must be the URL printed")
	}
}

func TestPKCELoginRefusesAnEmptyCode(t *testing.T) {
	_, err := pkceLogin(strings.NewReader("\n"), io.Discard, "http://unused.invalid", "openrouter", "", nil)
	var ce *cliError
	if !errors.As(err, &ce) || ce.code != 2 || ce.msg != "no code entered" {
		t.Errorf("err %v", err)
	}
}

func TestAuthURLPinsTheWorkspace(t *testing.T) {
	u, _ := url.Parse(authURL("chal", "harn-host", "ws-uuid-1"))
	if got := u.Query().Get("required_workspace_id"); got != "ws-uuid-1" {
		t.Errorf("required_workspace_id %q", got)
	}
}
