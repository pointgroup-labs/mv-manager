#!/bin/bash
# Colorize monad JSON logs by level

while IFS= read -r line; do
    [[ "$line" == *"keepalive"* ]] && continue

    if [[ "$line" == *'"ERROR"'* ]]; then
        echo -e "\033[31m$line\033[0m"
    elif [[ "$line" == *'"WARN"'* ]]; then
        echo -e "\033[33m$line\033[0m"
    elif [[ "$line" == *'"INFO"'* ]]; then
        echo -e "\033[32m$line\033[0m"
    elif [[ "$line" == *'"DEBUG"'* ]]; then
        echo -e "\033[2m$line\033[0m"
    else
        echo "$line"
    fi
done
