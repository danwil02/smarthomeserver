package main

import (
	"context"
	"net"
	"time"

	"github.com/foogod/go-powerwall"
	influxdb2 "github.com/influxdata/influxdb-client-go/v2"
	"github.com/influxdata/influxdb-client-go/v2/api/write"

	"go.uber.org/zap"
)

type powerwallCollector struct {
	pw     *powerwall.Client
	client influxdb2.Client
	org    string
	bucket string
	logger *zap.Logger
}

func NewPowerwallCollector(client *powerwall.Client, influxClient influxdb2.Client, org, bucket string, logger *zap.Logger) *powerwallCollector {
	return &powerwallCollector{
		pw:     client,
		client: influxClient,
		org:    org,
		bucket: bucket,
		logger: logger,
	}
}

func (c *powerwallCollector) writePoints(points []*write.Point) {
	writeAPI := c.client.WriteAPIBlocking(c.org, c.bucket)
	for _, point := range points {
		err := writeAPI.WritePoint(context.Background(), point)
		if err != nil {
			c.logger.Error("Error writing point to InfluxDB", zap.Error(err))
		}
		c.logger.Debug("Wrote point to InfluxDB", zap.Any("point", *point))
	}
}

func (c *powerwallCollector) Collect() {
	c.logger.Debug("Collecting metrics...")

	writeAPI := c.client.WriteAPIBlocking(c.org, c.bucket)

	status, err := c.pw.GetStatus()
	if err != nil {
		c.logger.Error("Error fetching status info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		points := []*write.Point{
			influxdb2.NewPoint("powerwall_info",
				map[string]string{"version": status.Version, "git_hash": status.GitHash},
				map[string]interface{}{"value": 1},
				time.Now()),
			influxdb2.NewPoint("powerwall_uptime_seconds",
				nil,
				map[string]interface{}{"value": status.UpTime.Seconds()},
				time.Now()),
			influxdb2.NewPoint("powerwall_commission_count",
				nil,
				map[string]interface{}{"value": status.CommissionCount},
				time.Now()),
		}
		c.writePoints(points)
		c.logger.Debug("Wrote status info to InfluxDB")
	}

	soe, err := c.pw.GetSOE()
	if err != nil {
		c.logger.Error("Error fetching SOE info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		point := influxdb2.NewPoint("powerwall_charge_ratio",
			nil,
			map[string]interface{}{"value": soe.Percentage / 100},
			time.Now())
		err := writeAPI.WritePoint(context.Background(), point)
		if err != nil {
			c.logger.Error("Error writing point to InfluxDB:", zap.Error(err))
		} else {
			c.logger.Debug("Wrote SOE info to InfluxDB")
		}
	}

	opdata, err := c.pw.GetOperation()
	if err != nil {
		c.logger.Error("Error fetching operation info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		points := []*write.Point{
			influxdb2.NewPoint("powerwall_operation_mode",
				map[string]string{"mode": opdata.RealMode},
				map[string]interface{}{"value": 1},
				time.Now()),
			influxdb2.NewPoint("powerwall_reserve_ratio",
				nil,
				map[string]interface{}{"value": opdata.BackupReservePercent / 100},
				time.Now()),
		}
		c.writePoints(points)
		c.logger.Debug("Wrote operation info to InfluxDB")
	}

	sitemaster, err := c.pw.GetSitemaster()
	if err != nil {
		c.logger.Error("Error fetching sitemaster info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		points := []*write.Point{
			influxdb2.NewPoint("powerwall_sitemaster_running",
				nil,
				map[string]interface{}{"value": boolToFloat64(sitemaster.Running)},
				time.Now()),
			influxdb2.NewPoint("powerwall_sitemaster_connected",
				nil,
				map[string]interface{}{"value": boolToFloat64(sitemaster.ConnectedToTesla)},
				time.Now()),
			influxdb2.NewPoint("powerwall_power_supply_mode",
				nil,
				map[string]interface{}{"value": boolToFloat64(sitemaster.PowerSupplyMode)},
				time.Now()),
		}
		if sitemaster.CanReboot != "Yes" {
			points = append(points, influxdb2.NewPoint("powerwall_sitemaster_busy",
				map[string]string{"reason": sitemaster.CanReboot},
				map[string]interface{}{"value": 1},
				time.Now()))
		}

		c.writePoints(points)
		c.logger.Debug("Wrote sitemaster info to InfluxDB")
	}

	problems, err := c.pw.GetProblems()
	if err != nil {
		c.logger.Error("Error fetching troubleshooting info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		point := influxdb2.NewPoint("powerwall_problems_detected_count",
			nil,
			map[string]interface{}{"value": float64(len(problems.Problems))},
			time.Now())
		err := writeAPI.WritePoint(context.Background(), point)
		if err != nil {
			c.logger.Error("Error writing point to InfluxDB:", zap.Error(err))
		} else {
			c.logger.Debug("Wrote troubleshooting info to InfluxDB")
		}
	}

	sysstatus, err := c.pw.GetSystemStatus()
	if err != nil {
		c.logger.Error("Error fetching system_status info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		points := []*write.Point{
			influxdb2.NewPoint("powerwall_full_pack_joules",
				nil,
				map[string]interface{}{"value": sysstatus.NominalFullPackEnergy * 3600},
				time.Now()),
			influxdb2.NewPoint("powerwall_remaining_joules",
				nil,
				map[string]interface{}{"value": sysstatus.NominalEnergyRemaining * 3600},
				time.Now()),
			influxdb2.NewPoint("powerwall_island_state",
				map[string]string{"state": sysstatus.SystemIslandState},
				map[string]interface{}{"value": 1},
				time.Now()),
		}
		for _, block := range sysstatus.BatteryBlocks {
			serial := block.PackageSerialNumber
			points = append(points, []*write.Point{
				influxdb2.NewPoint("powerwall_battery_info",
					map[string]string{"serial": serial, "partno": block.PackagePartNumber, "version": block.Version},
					map[string]interface{}{"value": 1},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_full_pack_joules",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": block.NominalFullPackEnergy * 3600},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_remaining_joules",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": block.NominalEnergyRemaining * 3600},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_output_volts",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": block.VOut},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_output_amps",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": block.IOut},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_output_hz",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": block.FOut},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_off_grid",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": boolToFloat64(block.OffGrid)},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_island_state",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": boolToFloat64(block.VfMode)},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_wobble_detected",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": boolToFloat64(block.WobbleDetected)},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_charge_power_clamped",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": boolToFloat64(block.ChargePowerClamped)},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_backup_ready",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": boolToFloat64(block.BackupReady)},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_pinv_state",
					map[string]string{"serial": serial, "state": block.PinvState},
					map[string]interface{}{"value": 1},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_pinv_grid_state",
					map[string]string{"serial": serial, "state": block.PinvGridState},
					map[string]interface{}{"value": 1},
					time.Now()),
				influxdb2.NewPoint("powerwall_battery_opseq_state",
					map[string]string{"serial": serial, "state": block.OpSeqState},
					map[string]interface{}{"value": 1},
					time.Now()),
			}...)
			if block.EnergyCharged != 0 {
				points = append(points, influxdb2.NewPoint("powerwall_battery_charged_joules_total",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": float64(block.EnergyCharged) * 3600},
					time.Now()))
			}
			if block.EnergyDischarged != 0 {
				points = append(points, influxdb2.NewPoint("powerwall_battery_discharged_joules_total",
					map[string]string{"serial": serial},
					map[string]interface{}{"value": float64(block.EnergyDischarged) * 3600},
					time.Now()))
			}
		}

		c.writePoints(points)
		c.logger.Debug("Wrote system_status info to InfluxDB")
	}

	aggs, err := c.pw.GetMetersAggregates()
	if err != nil {
		c.logger.Error("Error fetching meter aggregates info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		for cat, data := range *aggs {
			points := []*write.Point{
				influxdb2.NewPoint("powerwall_instant_power_watts",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantPower},
					time.Now()),
				influxdb2.NewPoint("powerwall_instant_reactive_power_watts",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantReactivePower},
					time.Now()),
				influxdb2.NewPoint("powerwall_instant_apparent_power_watts",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantApparentPower},
					time.Now()),
				influxdb2.NewPoint("powerwall_frequency_hz",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.Frequency},
					time.Now()),
				influxdb2.NewPoint("powerwall_instant_average_volts",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantAverageVoltage},
					time.Now()),
				influxdb2.NewPoint("powerwall_instant_average_amps",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantAverageCurrent},
					time.Now()),
				influxdb2.NewPoint("powerwall_instant_total_amps",
					map[string]string{"category": cat},
					map[string]interface{}{"value": data.InstantTotalCurrent},
					time.Now()),
			}
			if data.EnergyExported != 0 {
				points = append(points, influxdb2.NewPoint("powerwall_exported_joules_total",
					map[string]string{"category": cat},
					map[string]interface{}{"value": float64(data.EnergyExported) * 3600},
					time.Now()))
			}
			if data.EnergyImported != 0 {
				points = append(points, influxdb2.NewPoint("powerwall_imported_joules_total",
					map[string]string{"category": cat},
					map[string]interface{}{"value": float64(data.EnergyImported) * 3600},
					time.Now()))
			}

			c.writePoints(points)
			c.logger.Debug("Wrote meter aggregates info to InfluxDB")

			devs, err := c.pw.GetMeters(cat)
			if err != nil {
				c.logger.Error("Error fetching detailed meter info", zap.Error(err))
			} else {
				for _, dev := range *devs {
					devtype := dev.Type
					serial := dev.Connection.DeviceSerial
					data := dev.CachedReadings
					points := []*write.Point{
						influxdb2.NewPoint("powerwall_dev_instant_power_watts",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantPower},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_instant_reactive_power_watts",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantReactivePower},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_instant_apparent_power_watts",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantApparentPower},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_frequency_hz",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.Frequency},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_instant_average_volts",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantAverageVoltage},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_instant_average_amps",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantAverageCurrent},
							time.Now()),
						influxdb2.NewPoint("powerwall_dev_instant_total_amps",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": data.InstantTotalCurrent},
							time.Now()),
					}
					if data.EnergyExported != 0 {
						points = append(points, influxdb2.NewPoint("powerwall_dev_exported_joules_total",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": float64(data.EnergyExported) * 3600},
							time.Now()))
					}
					if data.EnergyImported != 0 {
						points = append(points, influxdb2.NewPoint("powerwall_dev_imported_joules_total",
							map[string]string{"category": cat, "type": devtype, "serial": serial},
							map[string]interface{}{"value": float64(data.EnergyImported) * 3600},
							time.Now()))
					}

					c.writePoints(points)
					c.logger.Debug("Wrote detailed meter info to InfluxDB")
				}
			}
		}
	}

	nets, err := c.pw.GetNetworks()
	if err != nil {
		c.logger.Error("Error fetching networks info", zap.Error(err))
		if _, ok := err.(net.Error); ok {
			return
		}
	} else {
		for _, net := range *nets {
			name := net.NetworkName
			nettype := net.Interface
			points := []*write.Point{
				influxdb2.NewPoint("powerwall_network_enabled",
					map[string]string{"type": nettype, "name": name},
					map[string]interface{}{"value": boolToFloat64(net.Enabled)},
					time.Now()),
				influxdb2.NewPoint("powerwall_network_active",
					map[string]string{"type": nettype, "name": name},
					map[string]interface{}{"value": boolToFloat64(net.Active)},
					time.Now()),
				influxdb2.NewPoint("powerwall_network_primary",
					map[string]string{"type": nettype, "name": name},
					map[string]interface{}{"value": boolToFloat64(net.Primary)},
					time.Now()),
			}
			iface := net.IfaceNetworkInfo
			if iface.NetworkName != "" {
				points = append(points, influxdb2.NewPoint("powerwall_network_state",
					map[string]string{"type": nettype, "name": name, "state": iface.State, "reason": iface.StateReason},
					map[string]interface{}{"value": 1},
					time.Now()))
				if iface.SignalStrength != 0 {
					points = append(points, influxdb2.NewPoint("powerwall_network_signal_strength",
						map[string]string{"type": nettype, "name": name},
						map[string]interface{}{"value": float64(iface.SignalStrength)},
						time.Now()))
				}
			}

			c.writePoints(points)
		}
	}
}

func boolToFloat64(b bool) float64 {
	if b {
		return 1
	}
	return 0
}
