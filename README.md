# Azure Data Factory and Modern Data Warehouse setup
### Based on:
*https://github.com/solliancenet/tech-immersion-data-ai/tree/master/environment-setup/data/6*

### Used to deliver labs
lab 1 - https://github.com/solliancenet/tech-immersion-data-ai/tree/master/data-exp6

lab 1 (short on-line workshop) - 

lab 2 - https://github.com/SpektraSystems/Analytics-Airlift/blob/master/ModernDataWarehouse-Analytics-In-A-Day.md

### Info
Script initializes environment for delivery above hands-on labs. However it requires some manual work:
- set values for variables: *rg*
- generate databricks token and configure it with your databricks cli `databricks configure`, add token to kv secrets `databricks-token`
- create Key Vault-backed secrets (name: `key-vault-secrets`) https://docs.azuredatabricks.net/user-guide/secrets/secret-scopes.html#akv-ss
- sql dw
    - add ip addres do the sql server firewall
    - `CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Password.1!!';`
- adjust adf connections
    - adls
    - blob
    - databricks (create and run cluster before that)


## Pre-requisites / Dependencies
- `az login` firstly
- `pip install databricks-cli`
- install jq -> `sudo apt-get install jq` -> or here https://stedolan.github.io/jq/download/
- Install Databricks CLI -> `pip install databricks-cli`

## Deployment list:
- Service principal account
- Azure Data Lake Storage Gen 2
- Azure Data Factory with pipeline (TODO: check if pipeline is properly connected to other resources)
- CosmoDB
- Blob storage
- Key Vault
- Azure Databricks
