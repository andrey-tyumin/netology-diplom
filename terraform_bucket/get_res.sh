#!/bin/bash
echo "sa-diplom access key : " `terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.access_key'`
echo "sa-diplom secret key : " `terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.secret_key'`
echo "sa-diplom accout id : " `terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.service_account_id'`
# export TF_VAR_SADIPLOMID=`terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.service_account_id'`
cp ./sa-diplom-key.json ../terraform/