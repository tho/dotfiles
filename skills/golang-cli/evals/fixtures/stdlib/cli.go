package cli

import (
	"flag"
	"fmt"
	"io"
	"strconv"
)

// Run prints input count times. It returns a process status without exiting.
func Run(args []string, lookup func(string) (string, bool), out, diagnostics io.Writer) int {
	fs := flag.NewFlagSet("repeat", flag.ContinueOnError)
	fs.SetOutput(diagnostics)
	count := fs.Int("count", 0, "repetitions")
	verbose := fs.Bool("verbose", false, "diagnostics")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if value, ok := lookup("COUNT"); ok {
		*count, _ = strconv.Atoi(value)
	}
	if value, ok := lookup("VERBOSE"); ok {
		*verbose, _ = strconv.ParseBool(value)
	}
	if fs.NArg() != 1 {
		return 2
	}
	if *verbose {
		fmt.Fprintln(diagnostics, "running")
	}
	for i := 0; i < *count; i++ {
		fmt.Fprintln(out, fs.Arg(0))
	}
	return 0
}
