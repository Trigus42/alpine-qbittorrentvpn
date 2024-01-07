package main

import (
	"crypto/rand"
	"crypto/sha512"
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	
	"golang.org/x/crypto/pbkdf2"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage:", os.Args[0], "<password> [<salt>] [<iterations>]")
		os.Exit(1)
	}

	password := os.Args[1]

	var salt []byte
	var err error = nil
	if len(os.Args) > 2 {
		salt, err = base64.StdEncoding.DecodeString(os.Args[2])
		if err != nil {
			fmt.Printf("Failed to decode salt from base64: %v\n", err)
			os.Exit(1)
		}
	} else {
		salt = make([]byte, 16)
		rand.Read(salt)
	}

	iterations := 100000
	if len(os.Args) > 3 {
		iterations, err = strconv.Atoi(os.Args[3])
		if err != nil {
			fmt.Println("Failed to parse iterations count: ", err)
			os.Exit(1)
		}
	}

	dk := pbkdf2.Key([]byte(password), salt, iterations, 64, sha512.New)

	fmt.Printf("%s\n", base64.StdEncoding.EncodeToString(salt))
	fmt.Printf("%s\n", base64.StdEncoding.EncodeToString(dk))
}