package iosbind

import "fmt"

func StartTun2Socks(fd, mtu, socksPort int, socksUser, socksPass string) error {
	return fmt.Errorf("tun2socks is only available on iOS/Android")
}

func StopTun2Socks() {}
