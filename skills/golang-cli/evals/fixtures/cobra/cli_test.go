package cli

import (
	"bytes"
	"errors"
	"testing"
)

func TestDryRun(t *testing.T) {
	var out bytes.Buffer
	calls := 0
	cmd := NewCommand(&out, func(string) error { calls++; return nil })
	cmd.SetArgs([]string{"rm", "--dry-run", "data.txt"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if calls != 0 || out.String() != "would remove data.txt\n" {
		t.Fatalf("calls=%d out=%q", calls, out.String())
	}
}
func TestExistingBehavior(t *testing.T) {
	for _, args := range [][]string{{"rm", "data.txt"}, {"rm", "--dry-run=false", "data.txt"}} {
		var out bytes.Buffer
		calls := 0
		want := errors.New("remove failed")
		cmd := NewCommand(&out, func(target string) error {
			calls++
			if target != "data.txt" {
				t.Fatalf("target %q", target)
			}
			return want
		})
		cmd.SetArgs(args)
		if err := cmd.Execute(); !errors.Is(err, want) || calls != 1 {
			t.Fatalf("err=%v calls=%d", err, calls)
		}
	}
}
func TestHelpAndArgs(t *testing.T) {
	for _, args := range [][]string{{"rm", "--help"}, {"--help"}, {"rm", "--dry-run"}} {
		var out bytes.Buffer
		calls := 0
		cmd := NewCommand(&out, func(string) error { calls++; return nil })
		cmd.SetArgs(args)
		err := cmd.Execute()
		if calls != 0 {
			t.Fatal("help/invalid args mutated")
		}
		if args[len(args)-1] == "--help" && err != nil {
			t.Fatal(err)
		}
		if args[len(args)-1] == "--dry-run" && err == nil {
			t.Fatal("missing target accepted")
		}
	}
}
