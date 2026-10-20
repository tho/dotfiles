package cli

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestHelpProcess(t *testing.T) {
	if os.Getenv("CLI_HELP_CHILD") == "1" {
		var out, diagnostics bytes.Buffer
		calls := 0
		err := Run([]string{"--help"}, &out, &diagnostics, func(string) error { calls++; return nil })
		if err != nil || calls != 0 || out.Len()+diagnostics.Len() == 0 {
			t.Fatalf("help err=%v calls=%d", err, calls)
		}
		fmt.Println("HELP_RETURNED_WITHOUT_EXECUTION")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestHelpProcess$")
	cmd.Env = append(os.Environ(), "CLI_HELP_CHILD=1")
	output, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(output), "HELP_RETURNED_WITHOUT_EXECUTION") {
		t.Fatalf("help exited or ran: %v %s", err, output)
	}
}
func TestArgumentsAndErrors(t *testing.T) {
	for _, name := range []string{"Ada", "Grace"} {
		calls := 0
		want := errors.New("execution failed")
		err := Run([]string{name}, io.Discard, io.Discard, func(got string) error {
			calls++
			if got != name {
				t.Fatalf("got %q", got)
			}
			return want
		})
		if !errors.Is(err, want) || calls != 1 {
			t.Fatalf("err=%v calls=%d", err, calls)
		}
	}
	calls := 0
	if err := Run([]string{"--unknown"}, io.Discard, io.Discard, func(string) error { calls++; return nil }); err == nil || calls != 0 {
		t.Fatalf("bad arg err=%v calls=%d", err, calls)
	}
}
