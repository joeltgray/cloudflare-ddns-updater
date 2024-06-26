#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                    	            # The email used to login 'https://dash.cloudflare.com'
auth_method=""                                      # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""    					    # Your API Token or Global API Key
declare -A zone_identifiers=(                       # Associative array mapping domains to zone identifiers
    ["example.com"]="myKeyHere"
    ["example2.com"]="myOtherKeyHere"
) 						    # Can be found in the "Overview" tab of your domain
record_names=("example.com" "submain.example2.com") # Which records you want to be synced Format: ("domain.com" "mydomain.net")
ttl=60                                              # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"


###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
    # Attempt to get the ip from other websites.
    ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
    # Extract just the ip from the ip line from cloudflare.
    ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    echo "DDNS Updater: Failed to find a valid IP." | tee >(logger -s)
    exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

echo "DDNS Updater: Check Initiated" | tee >(logger)
for record_name in "${record_names[@]}"; do
  echo "Updating IP for $record_name" | tee >(logger)
  if [[ $record_name =~ ([^.]+\.[^.]+)$ ]]; then
        domain="${BASH_REMATCH[1]}"
    else
        echo "Could not determine domain for $record_name" | tee >(logger)
        continue
    fi                  # Extract domain part from record name
  echo "domain extracted $domain"
  zone_identifier="${zone_identifiers[$domain]}" # Fetch the zone identifier based on domain
  url="https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name"

  echo "get url extracted is $url" | tee >(logger)
  record=$(curl -s -X GET $url \
                            -H "X-Auth-Email: $auth_email" \
                            -H "$auth_header $auth_key" \
                            -H "Content-Type: application/json")
  echo "Response for $record_name: $record" | tee >(logger)

	###########################################
	## Check if the domain has an A record
	###########################################
	if [[ $record == *"\"count\":0"* ]]; then
  		echo "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})" | tee >(logger -s)
  		exit 1
	fi

	###########################################
	## Get existing IP
	###########################################
	old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
	# Compare if they're the same
	if [[ $ip != $old_ip ]]; then
  		echo "DDNS Updater: IP ($ip) for ${record_name} has changed." | tee >(logger)

      ###########################################
      ## Set the record identifier from result
      ###########################################
      record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')

      ###########################################
      ## Change the IP@Cloudflare using the API
      ###########################################
      update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                          -H "X-Auth-Email: $auth_email" \
                          -H "$auth_header $auth_key" \
                          -H "Content-Type: application/json" \
                          --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")
	echo "Response to update for $record_name: $update" | tee >(logger)  
else
      echo "DDNS Updater: IP ($ip) for ${record_name} has not changed." | tee >(logger)
	fi
	
done
