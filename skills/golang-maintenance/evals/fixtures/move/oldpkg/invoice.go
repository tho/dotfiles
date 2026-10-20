package oldpkg

type Invoice struct{ cents int }

func New(cents int) Invoice  { return Invoice{cents: cents} }
func (i Invoice) Cents() int { return i.cents }
