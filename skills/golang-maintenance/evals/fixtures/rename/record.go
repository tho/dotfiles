package record

import (
	"bytes"
	"text/template"
)

type Record struct {
	Label string `json:"label"`
}

func Render(r Record) (string, error) {
	t, err := template.New("record").Parse("record={{.Label}}")
	if err != nil {
		return "", err
	}
	var out bytes.Buffer
	err = t.Execute(&out, r)
	return out.String(), err
}
