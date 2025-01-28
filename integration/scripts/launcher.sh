#!/bin/bash 
# Launcher script for geth and the entrypoint
set +x
cd `dirname \`realpath $0\``

case $1 in
  start)
    # 1337 is dev chain id
    nohup anvil --chain-id 1337 --accounts 1 > /dev/null 2>&1 &
	  sleep 10

      # `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` is Bundler EOA
	  cast send --unlocked --from $(cast rpc eth_accounts | tail -n 1 | tr -d '[]"') --value 1000ether 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 > /dev/null
	  (cd ../../lib/account-abstraction && yarn && yarn deploy --network localhost)
	  ../../@rundler/target/debug/rundler node --log.file out.log &
	  while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:3000/health)" != "200" ]]; do sleep 1 ; done
	  ;;
  stop)
	  pkill rundler
      pkill anvil
	  ;;
  *)
    cat <<EOF
usage:
  $0 start {v0_6|v0_7}
  $0 stop
EOF
esac
