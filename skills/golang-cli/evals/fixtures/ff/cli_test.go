package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestSources(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"name":"file"}`), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, env string
		args      []string
		want      string
	}{
		{"default", "", []string{"show"}, "world\n"},
		{"file", "", []string{"show", "-config", path}, "file\n"},
		{"env", "env", []string{"show", "-config", path}, "env\n"},
		{"flag", "env", []string{"show", "-config", path, "-name", "cli"}, "cli\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("APP_NAME", tc.env)
			var out bytes.Buffer
			if err := Run(tc.args, &out); err != nil || out.String() != tc.want {
				t.Fatalf("err=%v out=%q", err, out.String())
			}
		})
	}
}
func TestMissingFileAndArguments(t *testing.T) {
	t.Setenv("APP_NAME", "")
	for _, args := range [][]string{{"show", "-config", filepath.Join(t.TempDir(), "missing.json")}, {"show", "extra"}} {
		var out bytes.Buffer
		if err := Run(args, &out); err == nil {
			t.Fatalf("accepted %v", args)
		}
	}
	path := filepath.Join(t.TempDir(), "invalid.json")
	if err := os.WriteFile(path, []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := Run([]string{"show", "-config", path}, &out); err == nil {
		t.Fatal("accepted malformed JSON")
	}
}
