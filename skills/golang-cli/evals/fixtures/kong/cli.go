package cli

import (
	"github.com/alecthomas/kong"
	"io"
)

type arguments struct {
	Name string `arg:"" help:"Name to greet."`
}

// Run must accept explicit args and must not exit the process on help.
func Run(args []string, out, diagnostics io.Writer, execute func(string) error) error {
	var cli arguments
	parser, err := kong.New(&cli, kong.Writers(out, diagnostics))
	if err != nil {
		return err
	}
	if _, err = parser.Parse(args); err != nil {
		return err
	}
	return execute(cli.Name)
}
