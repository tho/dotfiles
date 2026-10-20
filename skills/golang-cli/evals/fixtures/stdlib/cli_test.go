package cli

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"
)

func lookup(values map[string]string) func(string) (string, bool) {
	return func(key string) (string, bool) { value, ok := values[key]; return value, ok }
}

func TestPrecedence(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		env  map[string]string
		want string
	}{
		{"explicit zero false", []string{"-count=0", "-verbose=false", "hello"}, map[string]string{"COUNT": "2", "VERBOSE": "true"}, ""},
		{"environment", []string{"hello"}, map[string]string{"COUNT": "2"}, "hello\nhello\n"},
		{"flag", []string{"-count=1", "hello"}, map[string]string{"COUNT": "2"}, "hello\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out, diagnostic bytes.Buffer
			code := Run(tc.args, lookup(tc.env), &out, &diagnostic)
			if code != 0 || out.String() != tc.want || diagnostic.Len() != 0 {
				t.Fatalf("code=%d out=%q err=%q", code, out.String(), diagnostic.String())
			}
		})
	}
}

func TestHelpAndValidation(t *testing.T) {
	for _, args := range [][]string{{"-h"}, {"-help"}, {"-count=3", "-h"}} {
		var out, diagnostic bytes.Buffer
		if code := Run(args, lookup(nil), &out, &diagnostic); code != 0 || out.Len()+diagnostic.Len() == 0 {
			t.Fatalf("help %v: %d", args, code)
		}
	}
	for _, tc := range []struct {
		args []string
		env  map[string]string
	}{
		{[]string{"-count=-1", "x"}, nil}, {[]string{"-count=11", "x"}, nil},
		{[]string{"x"}, map[string]string{"COUNT": ""}}, {[]string{"x"}, map[string]string{"COUNT": "bad"}},
		{[]string{"x"}, map[string]string{"VERBOSE": "bad"}}, {[]string{"-unknown", "x"}, nil}, {nil, nil},
	} {
		if code := Run(tc.args, lookup(tc.env), io.Discard, io.Discard); code != 2 {
			t.Fatalf("invalid %v/%v: %d", tc.args, tc.env, code)
		}
	}
}

type failedWriter struct{}

func (failedWriter) Write([]byte) (int, error) { return 0, errors.New("write failed") }
func TestOutputAndIsolation(t *testing.T) {
	if code := Run([]string{"-count=1", "x"}, lookup(nil), failedWriter{}, io.Discard); code != 1 {
		t.Fatalf("write status %d", code)
	}
	for _, verbose := range []bool{true, false} {
		var out, diagnostic bytes.Buffer
		args := []string{"-count=1", "x"}
		if verbose {
			args = []string{"-count=1", "-verbose", "x"}
		}
		if code := Run(args, lookup(nil), &out, &diagnostic); code != 0 || out.String() != "x\n" || (diagnostic.Len() > 0) != verbose {
			t.Fatalf("leak/output %d %q %q", code, out.String(), diagnostic.String())
		}
	}
	var diagnostic bytes.Buffer
	Run([]string{"-unknown"}, lookup(nil), io.Discard, &diagnostic)
	if strings.Count(diagnostic.String(), "flag provided but not defined") != 1 {
		t.Fatalf("duplicated diagnostic %q", diagnostic.String())
	}
}
