package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	Enabled bool `mapstructure:"enabled"`
	Port    int  `mapstructure:"port"`
}

// Load reads APP_ENABLED and APP_PORT. Port is required in range 1..65535.
func Load() (Config, error) {
	v := viper.New()
	v.SetEnvPrefix("APP")
	v.AutomaticEnv()
	var cfg Config
	err := v.Unmarshal(&cfg)
	return cfg, err
}
