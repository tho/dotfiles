package cli

import (
	"context"
	"flag"
	"fmt"
	"github.com/peterbourgon/ff/v3/ffcli"
	"io"
)

// Run's public command is "app show -name VALUE".
func Run(args []string, out io.Writer) error {
	fs := flag.NewFlagSet("show", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	name := fs.String("name", "world", "name")
	fs.String("config", "", "JSON file")
	show := &ffcli.Command{Name: "show", FlagSet: fs, Exec: func(_ context.Context, args []string) error { _, err := fmt.Fprintln(out, *name); return err }}
	root := &ffcli.Command{Name: "app", FlagSet: flag.NewFlagSet("app", flag.ContinueOnError), Subcommands: []*ffcli.Command{show}}
	return root.ParseAndRun(context.Background(), args)
}
