#!/usr/bin/env bash

# Copyright 2017 Mycroft AI Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SOURCE="${BASH_SOURCE[0]}"

script=${0}
script=${script##*/}
cd -P "$( dirname "$SOURCE" )"
DIR="$( pwd )"
VIRTUALENV_ROOT=${VIRTUALENV_ROOT:-"${DIR}/.venv"}

function help() {
    echo "${script}:  Mycroft command/service launcher"
    echo "usage: ${script} [command] [params]"
    echo
    echo "Services:"
    echo "  all                      runs core services: bus, audio, skills, voice"
    echo "  debug                    runs core services, then starts the CLI"
    echo
    echo "Services:"
    echo "  audio                    the audio playback service"
    echo "  bus                      the messagebus service"
    echo "  skills                   the skill service"
    echo "  voice                    voice capture service"
    # echo "  wifi                     wifi setup service"
    echo "  enclosure                mark_1 enclosure service"
    echo
    echo "Tools:"
    echo "  cli                      the Command Line Interface"
    echo "  unittest                 run mycroft-core unit tests (requires pytest)"
    echo "  skillstest               run the skill autotests for all skills (requires pytest)"
    echo
    echo "Utils:"
    echo "  audiotest                attempt simple audio validation"
    echo "  audioaccuracytest        more complex audio validation"
    echo "  sdkdoc                   generate sdk documentation"
    echo
    echo "Examples:"
    echo "  ${script} all"
    echo "  ${script} cli"
    echo "  ${script} unittest"

    exit 1
}

_script=""
function name-to-script-path() {
    case ${1} in
        "bus")             _script=${DIR}/mycroft/messagebus/service/main.py ;;
        "skills")          _script=${DIR}/mycroft/skills/main.py ;;
        "audio")           _script=${DIR}/mycroft/audio/main.py ;;
        "voice")           _script=${DIR}/mycroft/client/speech/main.py ;;
        "cli")             _script=${DIR}/mycroft/client/text/main.py ;;
        # "wifi")            _script=${DIR}/mycroft/client/wifisetup/main.py ;;
        "audioaccuracytest") _script=${DIR}/mycroft/audio-accuracy-test/audio_accuracy_test.py ;;
        "sdkdoc")          _script=${DIR}/doc/generate_sdk_docs.py ;;
        "enclosure")       _script=${DIR}/mycroft/client/enclosure/main.py ;;

        *)
            echo "Error: Unknown name '${1}'"
            exit 1
    esac
}

function source-venv() {
    # Enter Python virtual environment, unless under Docker
    if [ ! -f "/.dockerenv" ] ; then
        source ${VIRTUALENV_ROOT}/bin/activate
    fi
}

first_time=true
function launch-process() {
    if ($first_time) ; then
        echo "Initializing..."
        ${DIR}/scripts/prepare-msm.sh
        source-venv
        first_time=false
    fi

    name-to-script-path ${1}

    # Launch process in foreground
    echo "Starting $1"
    python3 ${_script} $_params
}

function launch-background() {
    if ($first_time) ; then
        echo "Initializing..."
        ${DIR}/scripts/prepare-msm.sh
        source-venv
        first_time=false
    fi

    name-to-script-path ${1}

    # Check if already running
    if [[ $( ps aux ) == *${_script}* ]] ; then
        echo "Restarting: ${1}"
        source stop-mycroft.sh ${1}
    else
        echo "Starting background service $1"
    fi

    # Security warning/reminder for the user
    if [[ "${1}" == "bus" ]] ; then
        echo "CAUTION: The Mycroft bus is an open websocket with no built-in security"
        echo "         measures.  You are responsible for protecting the local port"
        echo "         8181 with a firewall as appropriate."
    fi

    # Launch process in background, sending logs to standard location
    python3 ${_script} $_params >> /var/log/mycroft/${1}.log 2>&1 &
}

function launch-all() {
    echo "Starting all mycroft-core services"
    launch-background bus
    launch-background skills
    launch-background audio
    launch-background voice

    # Determine platform type
    if [[ -r /etc/mycroft/mycroft.conf ]] ; then
        mycroft_platform=$( jq -r ".enclosure.platform" < /etc/mycroft/mycroft.conf )
        if [[ $mycroft_platform = "mycroft_mark_1" ]] ; then
            # running on a Mark 1, start enclosure service
            launch-background enclosure
        fi
    fi
}

function check-dependencies() {
  if [ ! -f .installed ] || ! md5sum -c &> /dev/null < .installed ; then
    echo "Please update dependencies by running ./dev_setup.sh again."
    if command -v notify-send >/dev/null ; then
      notify-send "Mycroft Dependencies Outdated" "Run ./dev_setup.sh again"
    fi
    exit 1
  fi
}

_opt=$1
shift
_params=$@

check-dependencies

case ${_opt} in
    "all")
        launch-all
        ;;

    "bus")
        launch-background ${_opt}
        ;;
    "audio")
        launch-background ${_opt}
        ;;
    "skills")
        launch-background ${_opt}
        ;;
    "voice")
        launch-background ${_opt}
        ;;

    "debug")
        launch-all
        launch-process cli
        ;;

    "cli")
        launch-process ${_opt}
        ;;

    # TODO: Restore support for Wifi Setup on a Picroft, etc.
    # "wifi")
    #    launch-background ${_opt}
    #    ;;
    "unittest")
        source-venv
        pytest test/unittests/ --cov=mycroft "$@"
        ;;
    "skillstest")
        source-venv
        pytest test/integrationtests/skills/discover_tests.py "$@"
        ;;
    "audiotest")
        source-venv
        python3 -m mycroft.util.audio_test "${@:1}"
        ;;
    "audioaccuracytest")
        launch-process ${_opt}
        ;;
    "sdkdoc")
        launch-process ${_opt}
        ;;
    "enclosure")
        launch-background ${_opt}
        ;;

    *)
        help
        ;;
esac
