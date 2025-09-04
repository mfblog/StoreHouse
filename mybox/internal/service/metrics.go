package service

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// ProcessMetrics 进程指标
type ProcessMetrics struct {
	PID         int       `json:"pid"`
	CPUPercent  float64   `json:"cpu_percent"`
	MemoryBytes uint64    `json:"memory_bytes"`
	StartTime   time.Time `json:"start_time"`
}

// getProcessMetrics 获取进程性能指标
func getProcessMetrics(pid int) (*ProcessMetrics, error) {
	metrics := &ProcessMetrics{
		PID: pid,
	}
	
	// 获取内存使用量
	if memBytes, err := getProcessMemory(pid); err == nil {
		metrics.MemoryBytes = memBytes
	}
	
	// 获取CPU使用率
	if cpuPercent, err := getProcessCPU(pid); err == nil {
		metrics.CPUPercent = cpuPercent
	}
	
	// 获取启动时间
	if startTime, err := getProcessStartTime(pid); err == nil {
		metrics.StartTime = startTime
	}
	
	return metrics, nil
}

// getProcessMemory 获取进程内存使用量 (字节)
func getProcessMemory(pid int) (uint64, error) {
	statusPath := fmt.Sprintf("/proc/%d/status", pid)
	file, err := os.Open(statusPath)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "VmRSS:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				kb, err := strconv.ParseUint(fields[1], 10, 64)
				if err != nil {
					return 0, err
				}
				return kb * 1024, nil // 转换为字节
			}
		}
	}
	
	return 0, fmt.Errorf("无法找到内存使用信息")
}

// getProcessCPU 获取进程CPU使用率
func getProcessCPU(pid int) (float64, error) {
	statPath := fmt.Sprintf("/proc/%d/stat", pid)
	
	// 读取第一次数据
	cpuTime1, err := readProcessCPUTime(statPath)
	if err != nil {
		return 0, err
	}
	
	totalTime1, err := readSystemCPUTime()
	if err != nil {
		return 0, err
	}
	
	// 等待100毫秒
	time.Sleep(100 * time.Millisecond)
	
	// 读取第二次数据
	cpuTime2, err := readProcessCPUTime(statPath)
	if err != nil {
		return 0, err
	}
	
	totalTime2, err := readSystemCPUTime()
	if err != nil {
		return 0, err
	}
	
	// 计算CPU使用率
	cpuDelta := cpuTime2 - cpuTime1
	totalDelta := totalTime2 - totalTime1
	
	if totalDelta == 0 {
		return 0, nil
	}
	
	cpuPercent := (float64(cpuDelta) / float64(totalDelta)) * 100.0
	return cpuPercent, nil
}

// readProcessCPUTime 读取进程CPU时间
func readProcessCPUTime(statPath string) (uint64, error) {
	data, err := os.ReadFile(statPath)
	if err != nil {
		return 0, err
	}
	
	fields := strings.Fields(string(data))
	if len(fields) < 15 {
		return 0, fmt.Errorf("stat文件格式不正确")
	}
	
	// utime + stime (用户时间 + 系统时间)
	utime, err := strconv.ParseUint(fields[13], 10, 64)
	if err != nil {
		return 0, err
	}
	
	stime, err := strconv.ParseUint(fields[14], 10, 64)
	if err != nil {
		return 0, err
	}
	
	return utime + stime, nil
}

// readSystemCPUTime 读取系统总CPU时间
func readSystemCPUTime() (uint64, error) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, err
	}
	
	lines := strings.Split(string(data), "\n")
	if len(lines) == 0 {
		return 0, fmt.Errorf("无法读取CPU统计信息")
	}
	
	// 第一行是总CPU时间
	cpuLine := lines[0]
	if !strings.HasPrefix(cpuLine, "cpu ") {
		return 0, fmt.Errorf("CPU统计格式不正确")
	}
	
	fields := strings.Fields(cpuLine)
	if len(fields) < 5 {
		return 0, fmt.Errorf("CPU统计字段不足")
	}
	
	var totalTime uint64
	// 累加所有CPU时间字段 (user, nice, system, idle, iowait, irq, softirq)
	for i := 1; i < len(fields); i++ {
		if time, err := strconv.ParseUint(fields[i], 10, 64); err == nil {
			totalTime += time
		}
	}
	
	return totalTime, nil
}

// getProcessStartTime 获取进程启动时间
func getProcessStartTime(pid int) (time.Time, error) {
	statPath := fmt.Sprintf("/proc/%d/stat", pid)
	data, err := os.ReadFile(statPath)
	if err != nil {
		return time.Time{}, err
	}
	
	fields := strings.Fields(string(data))
	if len(fields) < 22 {
		return time.Time{}, fmt.Errorf("stat文件格式不正确")
	}
	
	// starttime字段
	starttime, err := strconv.ParseUint(fields[21], 10, 64)
	if err != nil {
		return time.Time{}, err
	}
	
	// 获取系统启动时间
	bootTime, err := getSystemBootTime()
	if err != nil {
		return time.Time{}, err
	}
	
	// 获取时钟频率
	clockTicks := getClockTicks()
	
	// 计算进程启动时间
	startSeconds := float64(starttime) / float64(clockTicks)
	processStartTime := bootTime.Add(time.Duration(startSeconds * float64(time.Second)))
	
	return processStartTime, nil
}

// getSystemBootTime 获取系统启动时间
func getSystemBootTime() (time.Time, error) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return time.Time{}, err
	}
	
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "btime ") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				bootTimestamp, err := strconv.ParseInt(fields[1], 10, 64)
				if err != nil {
					return time.Time{}, err
				}
				return time.Unix(bootTimestamp, 0), nil
			}
		}
	}
	
	return time.Time{}, fmt.Errorf("无法找到系统启动时间")
}

// getClockTicks 获取系统时钟频率
func getClockTicks() int64 {
	// 大多数系统默认为100
	return 100
}

// SystemMetrics 系统指标
type SystemMetrics struct {
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryPercent float64 `json:"memory_percent"`
	DiskPercent   float64 `json:"disk_percent"`
	LoadAverage   float64 `json:"load_average"`
}

// GetSystemMetrics 获取系统性能指标
func GetSystemMetrics() (*SystemMetrics, error) {
	metrics := &SystemMetrics{}
	
	// 获取CPU使用率
	if cpuPercent, err := getSystemCPU(); err == nil {
		metrics.CPUPercent = cpuPercent
	}
	
	// 获取内存使用率
	if memPercent, err := getSystemMemory(); err == nil {
		metrics.MemoryPercent = memPercent
	}
	
	// 获取磁盘使用率
	if diskPercent, err := getSystemDisk(); err == nil {
		metrics.DiskPercent = diskPercent
	}
	
	// 获取系统负载
	if loadAvg, err := getSystemLoad(); err == nil {
		metrics.LoadAverage = loadAvg
	}
	
	return metrics, nil
}

// getSystemCPU 获取系统CPU使用率
func getSystemCPU() (float64, error) {
	// 读取两次CPU统计，计算使用率
	stat1, err := readCPUStat()
	if err != nil {
		return 0, err
	}
	
	time.Sleep(100 * time.Millisecond)
	
	stat2, err := readCPUStat()
	if err != nil {
		return 0, err
	}
	
	totalDelta := (stat2.total - stat1.total)
	idleDelta := (stat2.idle - stat1.idle)
	
	if totalDelta == 0 {
		return 0, nil
	}
	
	cpuPercent := (1.0 - float64(idleDelta)/float64(totalDelta)) * 100.0
	return cpuPercent, nil
}

type cpuStat struct {
	total uint64
	idle  uint64
}

func readCPUStat() (*cpuStat, error) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return nil, err
	}
	
	lines := strings.Split(string(data), "\n")
	if len(lines) == 0 {
		return nil, fmt.Errorf("无法读取CPU统计")
	}
	
	cpuLine := lines[0]
	fields := strings.Fields(cpuLine)
	if len(fields) < 5 {
		return nil, fmt.Errorf("CPU统计格式错误")
	}
	
	var total, idle uint64
	
	// 累加所有时间
	for i := 1; i < len(fields); i++ {
		if val, err := strconv.ParseUint(fields[i], 10, 64); err == nil {
			total += val
			if i == 4 { // idle时间
				idle = val
			}
		}
	}
	
	return &cpuStat{total: total, idle: idle}, nil
}

// getSystemMemory 获取系统内存使用率
func getSystemMemory() (float64, error) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, err
	}
	
	var memTotal, memFree, memBuffers, memCached uint64
	
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		
		switch fields[0] {
		case "MemTotal:":
			memTotal, _ = strconv.ParseUint(fields[1], 10, 64)
		case "MemFree:":
			memFree, _ = strconv.ParseUint(fields[1], 10, 64)
		case "Buffers:":
			memBuffers, _ = strconv.ParseUint(fields[1], 10, 64)
		case "Cached:":
			memCached, _ = strconv.ParseUint(fields[1], 10, 64)
		}
	}
	
	if memTotal == 0 {
		return 0, fmt.Errorf("无法获取内存总量")
	}
	
	memUsed := memTotal - memFree - memBuffers - memCached
	memPercent := (float64(memUsed) / float64(memTotal)) * 100.0
	
	return memPercent, nil
}

// getSystemDisk 获取根分区磁盘使用率
func getSystemDisk() (float64, error) {
	// 简单实现，可以扩展为支持多个分区
	return getDiskUsage("/")
}

// getDiskUsage 获取指定路径的磁盘使用率
func getDiskUsage(path string) (float64, error) {
	// 这里可以使用syscall.Statfs或exec.Command("df")
	// 为简化，使用df命令
	output, err := runCommand("df", "-k", path)
	if err != nil {
		return 0, err
	}
	
	lines := strings.Split(output, "\n")
	if len(lines) < 2 {
		return 0, fmt.Errorf("df输出格式错误")
	}
	
	fields := strings.Fields(lines[1])
	if len(fields) < 5 {
		return 0, fmt.Errorf("df输出字段不足")
	}
	
	// 使用率在第5个字段，格式如"45%"
	usageStr := fields[4]
	if strings.HasSuffix(usageStr, "%") {
		usageStr = strings.TrimSuffix(usageStr, "%")
		if usage, err := strconv.ParseFloat(usageStr, 64); err == nil {
			return usage, nil
		}
	}
	
	return 0, fmt.Errorf("无法解析磁盘使用率")
}

// getSystemLoad 获取系统负载
func getSystemLoad() (float64, error) {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return 0, err
	}
	
	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return 0, fmt.Errorf("loadavg格式错误")
	}
	
	// 返回1分钟平均负载
	load, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, err
	}
	
	return load, nil
}
