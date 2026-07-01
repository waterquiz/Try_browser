#!/bin/bash
set -e

echo "=== Web Terminal Starting ==="

ttyd -p $PORT bash
