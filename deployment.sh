#!/bin/bash
# Dependencies:
# - az login first
# - pip install databricks-cli
# - install jq -> sudo apt-get install jq -> or here https://stedolan.github.io/jq/download/
# - Install Databricks CLI -> pip install databricks-cli
# echo -e "--Az login launching.... Use Ctrl+C if script is hanging \n"
# until az login; do echo "Command az login failed. Please login to your Lingaro subscription"; sleep 2; done

################################################################################################################

set -e
rg="aiad-pm-rg"
az_sp_name="tech-immersion-sp"

location=`az group show --name $rg --query location -o tsv`
sub_id=`az account show --query id -o tsv`
tenant_id=`az account show --query tenantId -o tsv`
databricks_account=`az account show --query user.name -o tsv`


### resources names (prefixes)
adlsname="adlsstrg"
adfname="tech-immersion-data-factory"
cosmodbname="aiadpmcosmos"
blobname="aiadblob"
kvname="aiadpmkv"
databricksName="aiadpmdb"

################################################################################################################

echo -e "-- Create service principal account -- \n"
az ad sp create-for-rbac -n $az_sp_name --scopes /subscriptions/$sub_id/resourceGroups/$rg -o json > service_principal.json

################################################################################################################

echo -e "-- ADLSv2 deployment -- \n"
output=`az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/adlsgen2_arm_template.json \
  --parameters arm_templates/adlsgen2_arm_template_parameters.json \
                "location=$location" \
                "storageAccountName=$adlsname"`

adlsname=`echo $output | jq '.properties.outputs.storageName.value' -r`

echo -e "-- Assign Storage Blob Data Contributor role to ADLSv2 -- \n"
az_sp_id=`cat service_principal.json | jq '.appId' -r`
az_sp_object_id=`az ad sp show --id $az_sp_id -o json | jq '.objectId' -r`

az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id "$az_sp_object_id" \
    --scope "/subscriptions/$sub_id/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$adlsname"

################################################################################################################

echo -e "-- Blob Storage deployment -- \n"

output=`az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/blob_arm_template.json \
  --parameters arm_templates/blob_arm_template_parameters.json \
                "storageAccountName=$blobname"`

echo -e "-- Insert Cars.csv and VehicleInfo.csv files to data-exp3-data container -- \n"

blob_name=`echo $output | jq '.properties.outputs.storageName.value' -r` #`az storage account list --query '[].name' -o tsv | grep $blobname`
export AZURE_STORAGE_CONNECTION_STRING=`az storage account show-connection-string --name $blob_name --resource-group $rg`

az storage blob upload-batch \
  --destination data-exp3-data \
  --source blob_files/data-exp3-data

echo -e "-- Insert trip_data_1.csv and trip_fare_1.csv files to data container -- \n"

az storage blob upload-batch \
  --destination data \
  --source blob_files/data

blob_primary_key=`az storage account keys list --account-name $blob_name --query '[0].value' -o tsv`

################################################################################################################

echo -e "-- Azure Data Factory deployment -- \n"
output=`az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/adf_arm_template.json \
  --parameters arm_templates/adf_arm_template_parameters.json \
                "factoryName=$adfname"`

adf_name=`echo $output | jq '.properties.outputs.adfName.value' -r` #`az resource list --query '[].name' | grep tech-immersion-data-factory`

echo -e "-- Deploy pipeline into Azure Data Factory -- \n"
az group deployment create \
  --resource-group $rg \
  --template-file adf_pipelines/adf_arm_pipeline_template.json \
  --parameters adf_pipelines/adf_arm_pipeline_template_parameters.json \
                "factoryName=$adf_name" \
                "ADLSGen2_properties_typeProperties_url=https://$adlsname.dfs.core.windows.net" \
                "AzureBlobStorage_connectionString='DefaultEndpointsProtocol=https;AccountName=$blob_name;EndpointSuffix=core.windows.net;'"

################################################################################################################

echo -e "-- Cosmos DB deployment -- \n"

az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/cosmos_arm_template.json \
  --parameters arm_templates/cosmos_arm_template_parameters.json \
                "name=$cosmodbname" \
                "location=$location"

cosmo_primary_key=`az cosmosdb keys list -g $rg --name $cosmodbname  -o json | jq '.primaryMasterKey' -r`
cosmo_uri=`az cosmosdb show -g $rg --name $cosmodbname -o json | jq '.documentEndpoint' -r`

################################################################################################################

echo -e "-- Key Vault deployment -- \n"

az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/kv_arm_template.json \
  --parameters arm_templates/kv_arm_template_parameters.json \
                "keyVaultName=$kvname"

echo -e "-- Set policy for service principal -- \n"

az_sp_pwd=`cat service_principal.json | jq '.password' -r`
az_sp_tenant=`cat service_principal.json | jq '.tenant' -r`
az_sp_id=`cat service_principal.json | jq '.appId' -r`
az_sp_object_id=`az ad sp show --id $az_sp_id -o json | jq '.objectId' -r`


az keyvault set-policy \
  --name $kvname \
  --object-id $az_sp_object_id \
  --secret-permissions list set

echo -e "-- Service principal login -- \n"
az login --service-principal -u $az_sp_id --password $az_sp_pwd --tenant $az_sp_tenant --allow-no-subscriptions

echo -e "-- Set secrets in key vault -- \n"
az keyvault secret set \
  --name "ADLS-Gen2-Account-Name" \
  --vault-name $kvname \
  --value "$adlsname"

az keyvault secret set \
  --name "Azure-Tenant-ID" \
  --vault-name $kvname \
  --value "$tenant_id"

az keyvault secret set \
  --name "ContosoAuto-SP-Client-ID" \
  --vault-name $kvname \
  --value "$sp_ap_id"

az keyvault secret set \
  --name "ContosoAuto-SP-Client-Key" \
  --vault-name $kvname \
  --value "$az_sp_pwd"

az keyvault secret set \
  --name "Cosmos-DB-Key" \
  --vault-name $kvname \
  --value "$cosmo_primary_key"

az keyvault secret set \
  --name "Cosmos-DB-Uri" \
  --vault-name $kvname \
  --value "$cosmo_uri"

az keyvault secret set \
  --name "Sql-Dw-Password" \
  --vault-name $kvname \
  --value 'Password.1!!'

az keyvault secret set \
  --name "Sql-Dw-Server-Name" \
  --vault-name $kvname \
  --value 'tech-immersion-sql-srv'

az keyvault secret set \
  --name "Storage-Account-Key" \
  --vault-name $kvname \
  --value "$blob_primary_key"

az keyvault secret set \
  --name "Storage-Account-Name" \
  --vault-name $kvname \
  --value "$blob_name"

################################################################################################################

echo -e "-- Databricks  deployment -- \n"
az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/databricks_arm_template.json \
  --parameters arm_templates/databricks_arm_template_parameters.json \
                "workspaceName=$databricksName"

until databricks configure --token; do echo "Error msg, waiting too long. Please provide input again"; sleep 2; done

# Example:
# - Databricks Host: https://northeurope.azuredatabricks.net/
# - token: xxx

echo -e "-- Create Databricks cluster -- \n"
databricks clusters create --json-file 'databricks_files/databricks_cluster.json' | jq '.cluster_id' -r > id
databricks_id=`cat id`; rm -f id

databricks libraries install --cluster-id $databricks_id --maven-coordinates com.microsoft.azure:azure-cosmosdb-spark_2.4.0_2.11:1.3.5

echo -e "-- Upload cluster setup notebook -- \n"
databricks workspace import databricks_files/Tech-Immersion.dbc -l python /Users/$databricks_account/Tech-Immersion -f dbc

# Not required:
# echo -e "-- Create and run job for 'Tech-Immersion.dbc' notebook -- \n"
# databricks_job=`databricks jobs create --json-file 'databricks_job.json' | jq '.job_id'`
# databricks jobs run-now --job-id $databricks_job


################################################################################################################
########################   Waiting for Lingaro subscription fix (Azure Synapse)   ##############################

echo -e "-- SQL Data Warehouse deployment -- \n"
az group deployment create \
  --resource-group $rg \
  --template-file arm_templates/sqldw_arm_template.json \
  --parameters arm_templates/sqldw_arm_template_parameters.json  

################################################################################################################