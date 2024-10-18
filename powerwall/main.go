package main

import (
	"os"
	"time"

	"github.com/foogod/go-powerwall"
	influxdb2 "github.com/influxdata/influxdb-client-go/v2"
	"github.com/urfave/cli/v2"
	"go.uber.org/zap"
)

func main() {
	app := &cli.App{
		Name:  "Powerwall Collector",
		Usage: "Collects data from Powerwall and writes to InfluxDB",
		Action: func(c *cli.Context) error {
			// Initialize zap logger
			logger, err := zap.NewDevelopment()
			if err != nil {
				panic(err)
			}
			defer logger.Sync()

			// Initialize Powerwall client
			// pwClient := powerwall.NewClient(
			// 	c.String("powerwall-address"),
			// 	c.String("powerwall-username"),
			// 	c.String("powerwall-password"),
			// )
			powerwall.SetLogFunc(func(i ...interface{}) { logger.Info("Powerwall", zap.Any("info", i)) })
			powerwall.SetErrFunc(func(s string, err error) { logger.Error(s, zap.Error(err)) })

			// pwClient := powerwall.NewClient("192.168.1.36", "danwil02@hotmail.com", "zqg6erf!awx!xun2YEF")
			pwClient := powerwall.NewClient("192.168.1.36", "", "CN322116G4J03U")
			// pwClient := powerwall.NewClient("192.168.1.36", "Customer", "4J03U")
			if pwClient == nil {
				logger.Fatal("Error initializing Powerwall client")
			}

			err = pwClient.DoLogin()
			if err != nil {
				logger.Fatal("Error logging in to Powerwall", zap.Error(err))
			}
			logger.Info("Powerwall client initialised", zap.String("address", c.String("powerwall-address")), zap.String("username", c.String("powerwall-username")))

			// Initialize InfluxDB client
			influxClient := influxdb2.NewClient(
				c.String("influxdb-url"),
				c.String("influxdb-token"),
			)
			defer influxClient.Close()
			logger.Info("influx client initialised")

			// Create a new Powerwall collector
			collector := NewPowerwallCollector(
				pwClient,
				influxClient,
				c.String("influxdb-org"),
				c.String("influxdb-bucket"),
				logger,
			)

			// Collect data periodically
			ticker := time.NewTicker(1 * time.Minute)
			defer ticker.Stop()

			collector.Collect()
			for range ticker.C {
				collector.Collect()
			}

			return nil
		},
	}

	app.Flags = []cli.Flag{
		&cli.StringFlag{
			Name:     "powerwall-address",
			Usage:    "Address of the Powerwall",
			EnvVars:  []string{"POWERWALL_ADDRESS"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "powerwall-username",
			Usage:    "Username for the Powerwall",
			EnvVars:  []string{"POWERWALL_USERNAME"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "powerwall-password",
			Usage:    "Password for the Powerwall",
			EnvVars:  []string{"POWERWALL_PASSWORD"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "influxdb-url",
			Usage:    "URL of the InfluxDB instance",
			EnvVars:  []string{"INFLUXDB_URL"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "influxdb-token",
			Usage:    "Token for the InfluxDB instance",
			EnvVars:  []string{"INFLUXDB_TOKEN"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "influxdb-org",
			Usage:    "Organization for the InfluxDB instance",
			EnvVars:  []string{"INFLUXDB_ORG"},
			Required: true,
		},
		&cli.StringFlag{
			Name:     "influxdb-bucket",
			Usage:    "Bucket for the InfluxDB instance",
			EnvVars:  []string{"INFLUXDB_BUCKET"},
			Required: true,
		},
	}

	err := app.Run(os.Args)
	if err != nil {
		panic(err)
	}
}

// func main() {
// 	client := powerwall.NewClient("192.168.1.36", "danwil02@hotmail.com", "zqg6erf!awx!xun2YEF")
// 	result, err := client.GetStatus()
// 	if err != nil {
// 		panic(err)
// 	}
// 	fmt.Printf("The gateway's ID number is: %s\nIt is running version: %s\n", result.Din, result.Version)
// 	client.GetSOE()
// 	client.GetOperation()
// 	client.GetSitemaster()
// 	client.GetProblems()
// 	client.GetSystemStatus()
// 	client.GetMetersAggregates()
// 	client.GetNetworks()
// }
