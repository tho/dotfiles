# Reorganizing an existing repository

Establish the current module roots, public imports, executable paths, generated files, tests, and build scripts before moving code. Capture existing build and test failures so they are distinguishable from migration regressions. Choose the new layout from consumer and release needs.

Take the inventory with the toolchain rather than by reading directories, once per module, since nested go.mod files stop `./...` traversal:

```sh
find . -name go.mod -not -path '*/vendor/*'                     # module roots
go list -f '{{.ImportPath}} {{.Name}}' ./... > before.txt       # packages; Name main marks binaries
go list -f '{{.ImportPath}}: {{join .Imports " "}} {{join .TestImports " "}} {{join .XTestImports " "}}' ./... | grep '<old/path>'   # in-repo importers
```

Rerun the package listing after the move and diff it against before.txt.

Map old import paths to new paths and identify external consumers before editing. A public package move is an API compatibility decision. Preserve the old path with a forwarding package or type aliases when suitable, or explicitly plan the breaking release and caller migration. Aliases cannot preserve every property, including package identity observed through reflection; check the contract actually promised.

Plan moves so every importer of an internal package stays inside its parent's tree, including across nested modules; `go build ./...` in each affected module reports violations and import cycles. A new common package without a cohesive responsibility only relocates a cycle.

Move affected tests and fixtures with their packages, and update imports, generator directives, embedded file paths, command build paths, and relevant automation. Verify newly separated modules explicitly from their own roots. Keep changes in buildable stages when the scope warrants them and separate module-boundary changes from unrelated dependency upgrades or behavioral edits.

The migration is complete when affected callers resolve, promised binaries build, relevant tests pass, and public-path compatibility is preserved or the intended break is documented. Inspect the final diff for unrelated changes. Report external consumers that could not be checked rather than treating local compilation as proof of compatibility.
