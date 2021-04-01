#!/bin/sh

openssl genrsa -aes256 -out swupdate.key
openssl rsa -in swupdate.key -out swupdate.pem -outform PEM -pubout
