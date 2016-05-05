wacker() {
  -wacker-usage() {
    cat <<'EOT'
usage: wacker [-v vpc_cidr] [-a az] [-s subnet_cidr] [-h ] [-o packer_options] template

Options:

  -v vpc_cidr       VPC cidr block (172.16.0.0/16 by default)
  -a az             Availability zone (ap-northeast-1a by default)
  -s subnet_cidr    Subnet cidr block (172.16.1.0/24 by default)
  -o packer_options Comma-Seprated Packer options
  -h                Show this help

EOT
  }

  -wacker-green() {
    local msg="$1"
    local esc="$(printf "\033")"
    local fg_green=32
    local _m="m"
    local default="[${_DEFAULT}${_m}"

    printf "${esc}[${fg_green}${_m}==> wacker: ${msg}${esc}${default}\n"
  }

  -wacker-red() {
    local msg="$1"
    local esc="$(printf "\033")"
    local fg_red=31
    local _m="m"
    local default="[${_DEFAULT}${_m}"

    printf "${esc}[${fg_red}${_m}==> wacker: ${msg}${esc}${default}\n" 1>&2
  }

  -wacker-validate() {
    local id="$1"
    local id_type="$2"

    if [[ "$id_type" == "vpc" ]]; then
      [[ "$id" =~ '^vpc-[a-z0-9]+$' ]]
    elif [[ "$id_type" == "subnet" ]]; then
      [[ "$id" =~ '^subnet-[a-z0-9]+$' ]]
    elif [[ "$id_type" == "igw" ]]; then
      [[ "$id" =~ '^igw-[a-z0-9]+$' ]]
    elif [[ "$id_type" == "rtb" ]]; then
      [[ "$id" =~ '^rtb-[a-z0-9]+$' ]]
    elif [[ "$id_type" == "rtb_assoc" ]]; then
      [[ "$id" =~ '^rtbassoc-[a-z0-9]+$' ]]
    else
      -wacker-usage
    fi
  }

  -wacker-cleanup() {
    if [[ -n "$rtb_assoc_id" ]] && -wacker-validate "$rtb_assoc_id" "rtb_assoc"; then
      aws ec2 disassociate-route-table --association-id "$rtb_assoc_id" \
        && -wacker-green "Route Table Association ID: $rtb_assoc_id removed"
    fi

    if [[ -n "$rtb_id" ]] && -wacker-validate "$rtb_id" "rtb"; then
      aws ec2 delete-route-table --route-table-id "$rtb_id" \
        && -wacker-green "Route Table ID: $rtb_id removed"
    fi

    if [[ -n "$igw_id" ]] && -wacker-validate "$igw_id" "igw"; then
      aws ec2 detach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id" \
        && aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" \
        && -wacker-green "Internet Gateway ID: $igw_id removed"
    fi

    if [[ -n "$subnet_id" ]] && -wacker-validate "$subnet_id" "subnet"; then
      aws ec2 delete-subnet --subnet-id "$subnet_id" \
        && -wacker-green "Subnet ID: $subnet_id removed"
    fi

    if [[ -n "$vpc_id" ]] && -wacker-validate "$vpc_id" "vpc"; then
      aws ec2 delete-vpc --vpc-id "$vpc_id" \
        && -wacker-green "Vpc ID: $vpc_id removed"
    fi
  }

  local cmd
  for cmd in "packer" "aws" "jq"; do
    type "$cmd" &>/dev/null || -wacker-red "Command: $cmd"
  done

  local template
  local vpc_cidr="172.16.0.0/16"
  local az="ap-northeast-1a"
  local subnet_cidr="172.16.1.0/16"
  local packer_options
  local vpc_id
  local subnet_id
  local igw_id
  local rtb_id

  local OPTARG OPTIND args
  while getopts ':t:v:a:s:o:h' args; do
    case "$args" in
      v) vpc_cidr="$OPTARG"
        ;;
      a)
        az="$OPTARG"
        ;;
      s)
        subnet_id="$OPTARG"
        ;;
      o)
        packer_options="$OPTARG"
        ;;
      h)
        -wacker-usage
        return 0
        ;;
      *)
        -wacker-usage
        return 1
        ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  template="$1"

  [[ -n "$template" && -f "$template" ]] || { -wacker-usage; return 1; }
  packer validate "$template" &>/dev/null || { -wacker-red "Template: $template"; return 1; }

  vpc_id="$(aws ec2 create-vpc --cidr-block "$vpc_cidr" \
    | jq --raw-output '.Vpc.VpcId')"

  if -wacker-validate "$vpc_id" "vpc"; then
    -wacker-green "Vpc ID: $vpc_id"
  else
    -wacker-red "Invalid Vpc ID: $vpc_id"
    return 1
  fi

  subnet_id="$(aws ec2 create-subnet \
    --vpc-id "$vpc_id" \
    --availability-zone "$az" \
    --cidr-block "$subnet_cidr" \
    | jq --raw-output '.Subnet.SubnetId')"

  if -wacker-validate "$subnet_id" "subnet"; then
    -wacker-green "Subnet ID: $subnet_id"
  else
    -wacker-red "Invalid Subnet ID: $subnet_id"
    -wacker-cleanup
    return 1
  fi

  igw_id="$(aws ec2 create-internet-gateway \
    | jq --raw-output '.InternetGateway.InternetGatewayId')"

  if -wacker-validate "$igw_id" "igw"; then
    aws ec2 attach-internet-gateway \
      --internet-gateway-id "$igw_id" \
      --vpc-id "$vpc_id"
    -wacker-green "Internet Gateway ID: $igw_id"
  else
    -wacker-red "Invalid Internet Gateway ID: $igw_id"
    -wacker-cleanup
    return 1
  fi

  rtb_id="$(aws ec2 create-route-table \
    --vpc-id "$vpc_id" \
    | jq --raw-output '.RouteTable.RouteTableId')"

  if -wacker-validate "$rtb_id" "rtb"; then
    aws ec2 create-route \
      --route-table-id "$rtb_id" \
      --destination-cidr-block "0.0.0.0/0" \
      --gateway-id "$igw_id" &>/dev/null
    -wacker-green "Route Table ID: $rtb_id"
  else
    -wacker-red "Invalid Route Table ID: $rtb_id"
    -wacker-cleanup
    return 1
  fi

  rtb_assoc_id="$(aws ec2 associate-route-table \
    --route-table-id "$rtb_id" \
    --subnet-id "$subnet_id" \
    | jq --raw-output 'select(.AssociationId != null).AssociationId')"

  if -wacker-validate "$rtb_assoc_id" "rtb_assoc"; then
    -wacker-green "Route Table Association ID: $rtb_assoc_id"
  else
    -wacker-red "Invalid Route Association ID: $rtb_assoc_id"
    -wacker-cleanup
    return 1
  fi

  printf "\n"
  packer build \
    -var "vpc_id=${vpc_id}" \
    -var "subnet_id=${subnet_id}" \
    $(echo "$packer_options" | awk '{gsub(/,/, " ", $0); print}') \
    "$template"

  printf "\n"
  -wacker-cleanup
}

# Local Variables:
# mode: Shell-Script
# sh-indentation: 2
# indent-tabs-mode: nil
# sh-basic-offset: 2
# End:
# vim: ft=zsh sw=2 ts=2 et
