package service

import (
	"os/exec"
	"strings"
)

// runCommand 执行命令并返回输出
func runCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.Output()
	return strings.TrimSpace(string(output)), err
}
