package cli

import (
	"github.com/spf13/cobra"
	"io"
)

// NewCommand constructs the existing public "files rm TARGET" interface.
func NewCommand(out io.Writer, remove func(string) error) *cobra.Command {
	root := &cobra.Command{Use: "files", SilenceErrors: true, SilenceUsage: true}
	root.SetOut(out)
	root.AddCommand(&cobra.Command{Use: "rm TARGET", Args: cobra.ExactArgs(1), RunE: func(cmd *cobra.Command, args []string) error { return remove(args[0]) }})
	return root
}
