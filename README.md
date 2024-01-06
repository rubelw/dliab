# dliab - Datalake In A Box

Includes a bash script to automatically deploy and setup the following to AWS EKS:
* OpenLdap
* OpenSearch
* Redis
* Postgresql
* Airflow
* OpenMetadata
* Trino
* Superset
* Apache Ranger (To be completed)
* DBT (To be completed)


On a centos instance, run:

```bash
./setup.py

./setup.py -d  # To tear down the EKS stack (don't foget to delete EBS volumes) 
```



## Deployment Steps
* Install pre-requisites 
* Clone helm chart repositories
* Clone dockerfile repositories
* Build and push custom docker files to AWS ECR
* Build and Deploy EKS cluster
* Deploy OpenLdap
* Deploy Postgress
* Deploy Redis
* Deploy Airflow
* Deploy OpenSearch
* Deploy OpenMetadata
* Deploy Trino
* Deploy Superset
* Port forwarding all resources to local environment
- kubectl port-forward services/openldap-chart 3389:389 &
- kubectl port-forward --namespace default svc/openmetadata 8585:8585 &
- kubectl port-forward --namespace default svc/airflow-chart-web 8080:8080 &
- kubectl port-forward services/openldap-chart-phpldapadmin 8081:80 &
- kubectl port-forward service/postgres-chart-postgresql 5432:5432 & 



## OpenLdap Credentials

* BindDN: cn=admin,dc=sirius,dc=com
* Bind Password:  passw0rd
* Local port: 3389

## PHPLdap
* BindDN: cn=admin,dc=sirius,dc=com
* Bind Password:  passw0rd
* Local port: 8081

## Postgres Database
* Local port: 5432
* Postgres user: postgres
* Postgres password: postgres

## OpenMetadata Admin Login
* Local port: 8585
* user email: ashaw@sirius.com
* password: passw0rd

## OpenMetadata Operations Login
* Local port: 8585
* user email: tfoster@sirius.com
* password: passw0rd

## Airflow Admin Login
* Local port: 8080
* username: ashaw
* password: passw0rd

## Airflow Operations Login
* Local port: 8080
* username: tfoster
* password: passw0rd

## Ranger Login
* Local port: 6050
* username:
* password: 


