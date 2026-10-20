package config

import (
	"testing"
)

func TestEnvironmentDecode(t *testing.T) {
	t.Setenv("APP_ENABLED", "true")
	t.Setenv("APP_PORT", "8080")
	cfg, err := Load()
	if err != nil || !cfg.Enabled || cfg.Port != 8080 {
		t.Fatalf("cfg=%+v err=%v", cfg, err)
	}
	t.Setenv("APP_ENABLED", "false")
	t.Setenv("APP_PORT", "9000")
	cfg, err = Load()
	if err != nil || cfg.Enabled || cfg.Port != 9000 {
		t.Fatalf("cfg=%+v err=%v", cfg, err)
	}
}
func TestInvalidConfiguration(t *testing.T) {
	t.Setenv("APP_ENABLED", "true")
	for _, value := range []string{"0", "-1", "65536", "bad", ""} {
		t.Setenv("APP_PORT", value)
		if _, err := Load(); err == nil {
			t.Fatalf("accepted invalid port %q", value)
		}
	}
	t.Setenv("APP_PORT", "8080")
	t.Setenv("APP_ENABLED", "bad")
	if _, err := Load(); err == nil {
		t.Fatal("accepted invalid boolean")
	}
}
