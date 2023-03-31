#!/bin/bash


# Global variables
SCRIPT_RELATIVE_DIR=$(dirname "${BASH_SOURCE[0]}")
ENVIRON_FILE=${SCRIPT_RELATIVE_DIR}/environ
# get past variables
touch ${ENVIRON_FILE}
source ${ENVIRON_FILE}

RUNNING=true

# menu functions

device_selection_menu(){
	current_device=$(adb -e emu avd name | head -1)
	if [ -z "${current_device}" ]
	then
		avd_list=$(${EMULATOR_FILE} -list-avds)
		choice=$(dialog --clear --stdout --title "Device Selection" --menu "Choose the device you want to use" 20 51 4 \
			0 "Create new device" \
			$(printf "%s\n" "${avd_list[@]}" | awk 'BEGIN{i=1}{print i++,$1}'))
		case $choice in
			0)
				state="DEVICE_CREATION"
				;;
			*)
				charles_port=$(dialog --clear --stdout --title "Proxy Setup" --inputbox "Please launch charles and enter the port it is running on:" 10 100)
				current_device=$(echo ${avd_list} | sed -n ${choice}p)
				x-terminal-emulator -T "Emulator" -e "bash -c '${EMULATOR_FILE} -avd ${current_device} -no-snapshot-load -writable-system -http-proxy http://localhost:${charles_port}'" 
				booting="yes"
				state="DEVICE_MENU"
				unset charles_port
				;;
		esac
		unset choice
		unset avd_list
	else
		dialog --clear --title "Info" --msgbox "Device already running, going to device menu" 10 100
		state="DEVICE_MENU"
	fi
}

new_device_menu(){
	#todo
	dialog --clear --title "Warning" --msgbox "Device creation not implemented yet" 10 100
	state="DEVICE_SELECTION"
}

device_menu(){
	if [ ! -z ${booting} ]
	then
		clear
		echo "Device booting"
		adb wait-for-device
		sleep 5
		unset booting
	fi
	installed_applications=$(adb shell "pm list packages -3"|cut -f 2 -d ":")
	adb wait-for-device root
	choice=$(dialog --clear --stdout --title "Device Menu" --menu "Select" 20 100 10 \
		0 "Install new application" \
		$(printf "%s\n" "${installed_applications[@]}" | awk 'BEGIN{i=1}{print i++,$1}') \
		s "Shutdown device and go back")
	case $choice in
		0)
			state="INSTALL_APP"
			;;
		s)
			adb -e emu kill
			unset current_device
			until [ "$(adb -e get-state 2>&1 > /dev/null)" = "error: no emulators found" ]; do sleep 1; done
			state="DEVICE_SELECTION"
			;;
		*)
			state="MANAGE_APP"
			selected_app=$(printf "%s\n" "${installed_applications[@]}" | sed -n ${choice}p)
			;;
	esac
	unset choice
	unset installed_applications
}

install_app_menu(){
	app_to_install=$(dialog --clear --stdout --title "Select the installation apk" --fselect $HOME/ 10 100)
	clear
	adb -e install ${app_to_install}
	state="DEVICE_MENU"
	unset app_to_install
}

manage_app_menu(){
	choice=$(dialog --clear --stdout --title "Device Menu" --menu "Select" 20 51 4 \
		0 "Launch app"\
		1 "Uninstall app"\
		2 "Back")
	case $choice in
		0)
			state="LAUNCH_APP"
			;;
		1)
			state="UNINSTALL_APP"
			;;
		2)
			state="DEVICE_MENU"
			unset selected_app
			;;
	esac
	unset choice
}

launch_app_menu(){
	adb shell pm clear ${selected_app}
	x-terminal-emulator -T "Application unpinning" -e "bash -c 'frida -U --no-pause -l ${UNPINNING_SCRIPT}  -f ${selected_app}'"
	state="RUNNING_APP_MENU"
}

uninstall_app_menu(){
	choice=$(dialog --clear --stdout --title "Uninstalling ${selected_app}" --menu "Are you sure?" 20 51 4 \
		0 "Yes"\
		1 "Back")
	
	case $choice in
		0)
			adb -e uninstall ${selected_app}
			unset selected_app
			state="DEVICE_MENU"
			;;
		1)
			state="MANAGE_APP"
			;;
	esac
	unset choice
}

running_app_menu(){
	choice=$(dialog --clear --stdout --title "Application Manager - Running : ${selected_app}" --menu "Options (both of these clear the application storage/cache):" 20 51 4 \
		0 "Close app"\
		1 "Restart app")
	
	adb shell pm clear ${selected_app}
	case $choice in
		0)
			unset selected_app
			state="DEVICE_MENU"
			;;
		1)
			state="LAUNCH_APP"
			;;
	esac
	unset choice
}

# check functions 

check_frida_server(){
	if [ ! $(adb shell "ps -A | grep frida") ]
	then
		while [[ ! $(adb shell "ls /data/local/tmp | grep frida") ]]
		do
			frida_server=`dialog --clear --stdout --title "Select the frida server file (make sure you are selecting the right architecture)" --fselect $SCRIPT_RELATIVE_DIR/ 10 100`
			adb push ${frida_server} /data/local/tmp
			adb shell "chmod 755 /data/local/tmp/$(basename ${frida_server})"
			unset frida_server
		done
		x-terminal-emulator -T "Frida server status" -e 'bash -c "echo Server running;adb shell "/data/local/tmp/$(adb shell "ls /data/local/tmp | grep frida")""'
		sleep 1
	fi
}

check_adb_package(){
	if ! command -v adb &> /dev/null
	then
		x-terminal-emulator -T "Installing adb" -e "bash -c 'sudo apt install adb'"
	fi
}

check_frida_package(){
	if ! command -v frida &> /dev/null
	then
		x-terminal-emulator -T "Installing frida" -e "bash -c 'sudo apt install frida'"
	fi
}

check_unpinning_script(){
	while [ ! -f "$UNPINNING_SCRIPT" ]
	do
		UNPINNING_SCRIPT=`dialog --clear --stdout --title "Select unpinning script" --fselect $SCRIPT_RELATIVE_DIR/ 10 100`
		declare -p UNPINNING_SCRIPT >> ${ENVIRON_FILE}
	done
}

check_emulator_file(){
	while [ ! -f "$EMULATOR_FILE" ]
	do
		EMULATOR_FILE=$(dialog --clear --stdout --title "First launch setup - Select emulator file" --fselect $HOME/ 10 100)
		declare -p EMULATOR_FILE >> ${ENVIRON_FILE}
		echo $(cat ${ENVIRON_FILE})
	done
}

check_avd_manager_file(){
	while [ ! -f "$AVD_MANAGER_FILE" ]
	do
		AVD_MANAGER_FILE=$(dialog --clear --stdout --title "First launch setup - Select avdmanager file" --fselect $(realpath $(dirname ${EMULATOR_FILE})/..)/ 10 100)
		declare -p AVD_MANAGER_FILE >> ${ENVIRON_FILE}
		echo $(cat ${ENVIRON_FILE})
	done
}


state="INIT"
while $RUNNING; do
	case $state in
		"INIT")
			check_emulator_file
			check_avd_manager_file
			state="DEVICE_SELECTION"
			;;
		"DEVICE_SELECTION")
			device_selection_menu
			;;
		"DEVICE_CREATION")
			new_device_menu
			;;
		"DEVICE_MENU")
			check_adb_package
			device_menu
			;;
		"LAUNCH_APP")
			check_frida_package
			check_frida_server
			check_unpinning_script
			launch_app_menu
			;;
		"UNINSTALL_APP")
			uninstall_app_menu
			;;
		"MANAGE_APP")
			manage_app_menu
			;;
		"INSTALL_APP")
			install_app_menu
			;;
		"RUNNING_APP_MENU")
			running_app_menu
			;;
		"BREAK")
			echo "Reaching BREAK State. Getting out of loop."
			RUNNING=false
			;;
	esac
done


echo "Script finished successfully."
exit 0
