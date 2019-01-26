package utils

import (
	"bytes"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
)

// DownloadFile download files from http
func DownloadFile(filepath string, url string) error {
	// Create the file
	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Get the data
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	if err != nil {
		return err
	}
	return nil
}

// RunCmd Runs command `name` with arguments `args`, env is the environmental settings
func RunCmd(env []string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	if env != nil && len(env) > 0 {
		cmd.Env = append(os.Environ(), env...)
	}

	stderrBytes := &bytes.Buffer{}
	cmd.Stderr = stderrBytes

	if err := cmd.Start(); err != nil {
		log.Fatal(err)
		return err
	}

	log.Println("Command running", name, args)
	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("Stderr %v", string(stderrBytes.Bytes()))
			log.Printf("Command finished with error: %v", err)
		} else {
			log.Printf("Command finished successfully")
		}
	}()
	return nil
}
