#!/bin/sh

openssl genrsa -aes256 -out priv.pem
openssl rsa -in priv.pem -out public.pem -outform PEM -pubout
