package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"runtime"
	"strings"
	"time"

	"github.com/harmony-one/experiment-deploy/experiment/utils"
)

type initReq struct {
	IP            string `json:"ip"`
	Port          string `json:"port"`
	SessionID     string `json:"sessionId"`
	BenchmarkArgs string `json:"benchmarkArgs"`
	TxgenArgs     string `json:"txgenArgs"`
	Role          string `json:"role"`
}

type updateReq struct {
	Bucket string `json:"bucket"`
	Folder string `json:"folder"`
	File   string `json:"file"`
}

type configReq struct {
	SessionID string `json:"sessionId"`
	ConfigURL string `json:"configURL"`
}

var (
	version string
	builtBy string
	builtAt string
	commit  string
)

type soliderSetting struct {
	ip                string
	port              string
	metricsProfileURL string
}

type sessionInfo struct {
	id                  string
	commanderIP         string
	commanderPort       string
	logFolder           string
	txgenAdditionalArgs []string
	nodeAdditionalArgs  []string
}

const (
	bucketName      = "richard-bucket-test"
	logFolderPrefix = "../tmp_log/"
)

var (
	setting       soliderSetting
	globalSession sessionInfo
	txgenArgs     = []string{
		"-max_num_txs_per_batch",
		"-log_folder",
		"-numSubset",
		"-duration",
		"-version",
		"-cross_shard_ratio",
	}
)

func printVersion(me string) {
	fmt.Fprintf(os.Stderr, "Harmony (C) 2018. %v, version %v-%v (%v %v)\n", path.Base(me), version, commit, builtBy, builtAt)
	os.Exit(0)
}

func killPort(port string) error {
	if runtime.GOOS == "windows" {
		command := fmt.Sprintf("(Get-NetTCPConnection -LocalPort %s).OwningProcess -Force", port)
		return utils.RunCmd("Stop-Process", "-Id", command)
	}
	command := fmt.Sprintf("lsof -i tcp:%s | grep LISTEN | awk '{print $2}' | xargs kill -9", port)
	return utils.RunCmd("/bin/bash", "-c", command)
}

func runInstance(role string) error {
	os.MkdirAll(globalSession.logFolder, os.ModePerm)

	if role == "client" {
		return runClient()
	}
	return runNode()
}

func runNode() error {
	log.Println("running instance")
	args :=
		append([]string{"-ip", setting.ip, "-port", setting.port, "-log_folder", globalSession.logFolder}, globalSession.nodeAdditionalArgs...)

	return utils.RunCmd("./harmony", args...)
}

func runClient() error {
	log.Println("running client")
	args :=
		append([]string{"-ip", setting.ip, "-port", setting.port, "-log_folder", globalSession.logFolder}, globalSession.txgenAdditionalArgs...)

	return utils.RunCmd("./txgen", args...)
}

// Index ...
func Index(vs []string, t string) int {
	for i, v := range vs {
		if v == t {
			return i
		}
	}
	return -1
}

// Include ...
func Include(vs []string, t string) bool {
	return Index(vs, t) >= 0
}

func initHandler(w http.ResponseWriter, r *http.Request) {
	var res string
	if r.Method != http.MethodGet {
		res = "Not Supported Method"
		io.WriteString(w, res)
		return
	}
	log.Println("Init Handler")
	if r.Body == nil {
		http.Error(w, "no data found in the init request", http.StatusBadRequest)
		return
	}

	var init initReq

	err := json.NewDecoder(r.Body).Decode(&init)
	if err != nil {
		log.Printf("Json decode failed %v\n", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	globalSession.id = init.SessionID
	globalSession.logFolder = fmt.Sprintf("%slog-%v", logFolderPrefix, init.SessionID)
	globalSession.nodeAdditionalArgs = nil
	globalSession.txgenAdditionalArgs = nil

	globalSession.txgenAdditionalArgs = append(globalSession.txgenAdditionalArgs, strings.Split(init.TxgenArgs, " ")...)
	globalSession.nodeAdditionalArgs = append(globalSession.nodeAdditionalArgs, strings.Split(init.BenchmarkArgs, " ")...)
	if err := runInstance(init.Role); err == nil {
		res = "Succeeded"
	} else {
		res = fmt.Sprintf("Failed init %v", err)
	}
	io.WriteString(w, res)
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
	var res string
	if r.Method != http.MethodGet {
		res = "Not Supported Method"
		io.WriteString(w, res)
		return
	}
	log.Println("Ping Handler")
	res = "Succeeded"
	io.WriteString(w, res)
}

func updateHandler(w http.ResponseWriter, r *http.Request) {
	var res string
	if r.Method != http.MethodGet {
		res = "Not Supported Method"
		io.WriteString(w, res)
		return
	}
	log.Println("Update Handler")

	if r.Body == nil {
		http.Error(w, "no data found in the update request", http.StatusBadRequest)
		return
	}

	var update updateReq

	err := json.NewDecoder(r.Body).Decode(&update)
	if err != nil {
		log.Printf("Json decode failed %v\n", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	downloadURL := fmt.Sprintf("http://%v.s3.amazonaws.com/%v/%v", update.Bucket, update.Folder, update.File)
	if err := utils.DownloadFile(update.File, downloadURL); err != nil {
		log.Println("Update failed: ", downloadURL)
		res = "Failed"
	} else {
		res = "Succeeded"
	}
	io.WriteString(w, res)
}

func killHandler(w http.ResponseWriter, r *http.Request) {
	var res string
	if r.Method != http.MethodGet {
		res = "Not Supported Method"
		io.WriteString(w, res)
		return
	}
	log.Println("Kill Handler")
	if err := killPort(setting.port); err == nil {
		res = "Succeeded"
	} else {
		res = "Failed"
	}
	io.WriteString(w, res)
}

func httpServer() {
	http.HandleFunc("/init", initHandler)
	http.HandleFunc("/ping", pingHandler)
	http.HandleFunc("/update", updateHandler)
	http.HandleFunc("/kill", killHandler)

	s := http.Server{
		Addr:           fmt.Sprintf("0.0.0.0:1%v", setting.port),
		Handler:        nil,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}

	log.Printf("HTTP server listen on port: 1%v", setting.port)
	log.Println("Supported API:")
	log.Println("/ping\t\t\tI'm alive!")
	log.Println("/init\t\t\tStart Benchmark/Txgen")
	log.Println("/update\t\t\tDownload/Update binary")
	log.Println("/kill\t\t\tKill Running Benchmark/Txgen")

	log.Fatalf(fmt.Sprintf("http server error: %v", s.ListenAndServe()))
}

func main() {
	ip := flag.String("ip", "127.0.0.1", "IP of the node.")
	port := flag.String("port", "9000", "port of the node.")
	versionFlag := flag.Bool("version", false, "Output version info")

	flag.Parse()

	if *versionFlag {
		printVersion(os.Args[0])
	}

	setting.ip = *ip
	setting.port = *port

	httpServer()
}
