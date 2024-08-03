#!/bin/bash
#
# Orion - An open-source user interface for the Odyssey 3d-printing engine.
# Copyright (C) 2024 TheContrappostoShop
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Function to display a help message
show_help() {
    echo "Usage: ./orionpi.sh [IP_ADDR] [USERNAME] [PASSWORD] (-a arch) (-c cpu) (-ro) (-r)"
    echo ""
    echo "Required Arguments:"
    echo "  IP_ADDR         IP address of the Raspberry Pi."
    echo "  USERNAME        Username for SSH authentication."
    echo "  PASSWORD        Password for SSH authentication."
    echo -e "Optional Arguments: (defaults in \033[0;31mred\033[0m)"
    echo -e "  -h, --help      Display this help message."
    echo -e "  -a, --arch      Host architecture. [\033[0;31marm\033[0m, arm64, x86]"
    echo -e "  -c, --cpu       Target CPU. [generic, pi3, \033[0;31mpi4\033[0m]"
    echo -e "  -ro             Run-only mode. Run OrionPi in run-only mode, no build or copy."
    echo -e "  -r              Release mode. Build OrionPi in release mode."
    exit 1
}

# Default values for optional arguments
arch="arm"
cpu="pi4"

# Parse command-line options
for arg in "$@"
do
    case $arg in
        -h|--help)
            show_help
            ;;
        -a|--arch)
            shift # Remove argument name from processing
            arch=$1
            shift # Remove argument value from processing
            ;;
        -c|--cpu)
            shift
            cpu=$1
            shift
            ;;
        -ro)
            run_only=true
            shift
            ;;
        -r)
            release=true
            shift
            ;;
        *)
            if [ -z "$ip" ]; then
                ip=$1
            elif [ -z "$user" ]; then
                user=$1
            elif [ -z "$password" ]; then
                password=$1
            fi
            shift
            ;;
    esac
done

# Check if IP address, username, and password were provided
if [ -z "$ip" ] || [ -z "$user" ] || [ -z "$password" ]; then
    show_help
fi

# Check if sshpass is installed, if not, install it using the appropriate package manager
if ! command -v sshpass &> /dev/null; then
    echo "sshpass is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hudochenkov/sshpass/sshpass
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get install -y sshpass
    else
        echo "Unsupported Operating System"
        exit 1
    fi
fi

# Function to show a waiting scroller
show_scroller() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'
    local msg=$2
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r[%c]  %s" "$spinstr" "$msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r[\033[0;32m✓\033[0m]  %s" "$msg"
}

# Function to print a right-aligned message
print_done() {
    local cols=$(tput cols)
    local time=$2
    # Add a leading space if time is less than 10 seconds
    if [ $time -lt 10 ]; then
        time=$(printf " %d" $time)
    fi
    local msg="Done. [$time""s]"
    local len=${#msg}
    local start_len=${#start_msg}
    local spaces=$((cols-start_len-len-8)) # Subtract 8 to account for color escape sequences and brackets
    printf "%*s\033[0;32m%s\033[0m\n" $spaces "" "$msg"
}

# Check if SSH port is open
output=$(ssh -o BatchMode=yes -o ConnectTimeout=3 $user@$ip 'exit' 2>&1)
if [[ $output == *"Connection refused"* ]] ||
[[ $output == *"Host is down"* ]] || 
[[ $output == *"no matching host key type"* ]] || 
[[ $output == *"Operation timed out"* ]]; then
    printf "\n\r[\033[0;31m✗\033[0m]\033[0;31m%s\033[0m\n" "  SSH Connection Failed! Please check your IP address."
    exit 1
fi

# Check if SSH password is correct
output=$(sshpass -p "$password" ssh -o ConnectTimeout=5 $user@$ip 'echo 2>&1' 2>&1)
if [[ $output == *"Permission denied, please try again."* ]]; then
    printf "\n\r[\033[0;31m✗\033[0m]\033[0;31m%s\033[0m\n" "  SSH Authentication Failed!"
    exit 1
fi

# SSH command to kill all instances of flutter-pi on the Raspberry Pi if it is running
start_msg="Terminating Existing OrionPi Instances"
printf "\n%s" "$start_msg"
start_time=$(date +%s)
(sshpass -p "$password" ssh $user@$ip 'pgrep flutter-pi > /dev/null && killall flutter-pi ' 2>&1 & show_scroller $! "$start_msg")
wait $!
end_time=$(date +%s)
print_done "Done. [$((end_time - start_time))s]" $((end_time - start_time))

if [ "$run_only" != true ]; then
    # Run flutterpi_tool build with progress bar
    start_msg="Building Flutter Bundle"
    printf "%s" "$start_msg"
    start_time=$(date +%s)
    if [ "$release" = true ]; then
        (flutterpi_tool build --arch=arm --cpu=pi4 --release > /dev/null 2>&1 & show_scroller $! "$start_msg")
    else
        (flutterpi_tool build --arch=arm --cpu=pi4 > /dev/null 2>&1 & show_scroller $! "$start_msg")
    fi
    wait $!
    end_time=$(date +%s)
    print_done "Done. [$((end_time - start_time))s]" $((end_time - start_time))

    # Run scp command with waiting scroller and password
    start_msg="Copying Files to Target"
    printf "%s" "$start_msg"
    start_time=$(date +%s)
    (sshpass -p "$password" scp -r ./build/flutter_assets $user@$ip:/home/$user/orion & show_scroller $! "$start_msg")
    wait $!
    end_time=$(date +%s)
    print_done "Done. [$((end_time - start_time))s]" $((end_time - start_time))
fi

# SSH command to kill all instances of flutter-pi on the Raspberry Pi
printf "\n\r[\033[0;32m✓\033[0m]\033[0;32m%s\033[0m\n" "  Running OrionPi on Raspberry Pi!"
printf "\r[i]""  Press \033[0;31mCtrl+C\033[0m to disconnect.\n\n"
if [ "$release" = true ]; then
    sshpass -p "$password" ssh $user@$ip 'flutter-pi --release --pixelformat=RGB565 /home/$user/orion'
else
    sshpass -p "$password" ssh $user@$ip 'flutter-pi --pixelformat=RGB565 /home/$user/orion'
fi
