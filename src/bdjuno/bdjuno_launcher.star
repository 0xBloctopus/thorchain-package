def launch_bdjuno(plan, chain_name):
    postgres_service = launch_postgres_service(plan, chain_name)

    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    # Launch the bdjuno service
    bdjuno_service, hasura_metadata_artifact = launch_bdjuno_service(plan, postgres_service, first_node, chain_name)

    # Launch hasura service
    hasura_service = launch_hasura_service(plan, postgres_service, chain_name, hasura_metadata_artifact)


    big_dipper_service = launch_big_dipper(plan, chain_name)

    # Launch nginx reverse proxy to access explorer
    launch_nginx(plan, big_dipper_service, hasura_service, first_node, chain_name)

    plan.print("BdJuno and Hasura started successfully")


def launch_postgres_service(plan, chain_name):

    # Upload SQL schema files to Kurtosis
    schema_files_artifact = plan.upload_files(
        src="github.com/LZeroAnalytics/bdjuno/database/schema",
        name="{}-schema-files".format(chain_name)
    )
    postgres_service = plan.add_service(
        name="{}-bdjuno-postgres".format(chain_name),
        config = ServiceConfig(
            image = "postgres:14.5",
            ports = {
                "db": PortSpec(number=5432, transport_protocol="TCP", application_protocol="postgres")
            },
            env_vars = {
                "POSTGRES_USER": "bdjuno",
                "POSTGRES_PASSWORD": "password",
                "POSTGRES_DB": "bdjuno"
            },
            files = {
                "/tmp/database/schema": schema_files_artifact
            }
        )
    )

    # Command to execute SQL files
    init_db_command = (
            "for file in /tmp/database/schema/*.sql; do " +
            "psql -U bdjuno -d bdjuno -f $file; " +
            "done"
    )

    plan.exec(
        service_name="{}-bdjuno-postgres".format(chain_name),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", init_db_command]
        )
    )

    return postgres_service


def launch_bdjuno_service(plan, postgres_service, node_service, chain_name):
    # Render the configuration file
    bdjuno_config_data = {
        "ChainPrefix": "thor",
        "NodeIP": node_service.ip_address,
        "PostgresIP": postgres_service.ip_address,
        "PostgresPort": postgres_service.ports["db"].number,
        "RpcPort": node_service.ports["rpc"].number,
        "GrpcPort": node_service.ports["grpc"].number
    }
    bdjuno_config_artifact = plan.render_templates(
        config = {
            "config.yaml": struct(
                template = read_file("templates/config.yaml.tmpl"),
                data = bdjuno_config_data
            )
        },
        name="{}-bdjuno-config".format(chain_name)
    )

    # Upload Hasura metadata files to Kurtosis
    hasura_metadata_artifact = plan.upload_files(
        src="github.com/LZeroAnalytics/bdjuno/hasura",
        name="{}-hasura-metadata".format(chain_name)
    )

    # Retrieve the genesis file
    genesis_file_artifact = plan.get_files_artifact(
        name = "{}-genesis-render".format(chain_name)
    )

    bdjuno_start_config = {
        "GenesisFilePath": "/tmp/genesis/genesis.json",
        "BdjunoHome": "/bdjuno/.bdjuno"
    }

    bdjuno_start_artifact = plan.render_templates(
        config = {
            "start_bdjuno.sh": struct(
                template = read_file("templates/start_bdjuno.sh.tmpl"),
                data = bdjuno_start_config
            )
        },
        name="{}-bdjuno-start".format(chain_name)
    )

    bdjuno_service = plan.add_service(
        name = "{}-bdjuno-service".format(chain_name),
        config = ServiceConfig(
            image = "tiljordan/bdjuno-thorchain:1.0.6",
            ports = {
                "bdjuno": PortSpec(number=26657, transport_protocol="TCP", wait = None),
                "actions": PortSpec(number=3000, transport_protocol="TCP", wait = None)
            },
            files = {
                "/bdjuno/.bdjuno": bdjuno_config_artifact,
                "/tmp/genesis": genesis_file_artifact,
                "/usr/local/bin/scripts": bdjuno_start_artifact,
            },
            cmd = ["/bin/sh", "/usr/local/bin/scripts/start_bdjuno.sh"],
        )
    )

    return bdjuno_service, hasura_metadata_artifact


def launch_hasura_service(plan, postgres_service, chain_name, hasura_metadata_artifact):
    hasura_service = plan.add_service(
        name = "{}-hasura".format(chain_name),
        config = ServiceConfig(
            image = "tiljordan/graphql-engine:v2.46.0",
            ports = {
                "graphql": PortSpec(number=8080, transport_protocol="TCP")
            },
            files = {
                "/hasura": hasura_metadata_artifact
            },
            env_vars = {
                "HASURA_GRAPHQL_UNAUTHORIZED_ROLE": "anonymous",
                "HASURA_GRAPHQL_DATABASE_URL": "postgresql://bdjuno:password@" + postgres_service.ip_address + ":" + str(postgres_service.ports["db"].number) + "/bdjuno",
                "HASURA_GRAPHQL_METADATA_DATABASE_URL": "postgresql://bdjuno:password@" + postgres_service.ip_address + ":" + str(postgres_service.ports["db"].number) + "/bdjuno",
                "PG_DATABASE_URL": "postgresql://bdjuno:password@" + postgres_service.ip_address + ":" + str(postgres_service.ports["db"].number) + "/bdjuno",
                "HASURA_GRAPHQL_ENABLE_CONSOLE": "true",
                "HASURA_GRAPHQL_DEV_MODE": "false",
                "HASURA_GRAPHQL_ENABLED_LOG_TYPES": "startup, http-log, webhook-log",
                "HASURA_GRAPHQL_ADMIN_SECRET": "myadminsecretkey",
                "HASURA_GRAPHQL_METADATA_DIR": "/hasura/metadata",
                "ACTION_BASE_URL": "http://{}-bdjuno-service:3000".format(chain_name),
                "HASURA_GRAPHQL_SERVER_PORT": "8080"
            }
        )
    )

    # Apply metadata automatically after Hasura starts using hasura CLI
    plan.exec(
        service_name="{}-hasura".format(chain_name),
        recipe=ExecRecipe(
            command=[
                "/bin/sh", "-c",
                """
                cd /hasura
                hasura metadata apply --endpoint http://localhost:8080 --admin-secret $HASURA_GRAPHQL_ADMIN_SECRET --skip-update-check
                """
            ]
        )
    )

    return hasura_service


def launch_big_dipper(plan,chain_name):
    big_dipper_service = plan.add_service(
        name="{}-big-dipper-service".format(chain_name),
        config=ServiceConfig(
            image="tiljordan/thorchain-ui:1.0.13",
            env_vars={
                "NEXT_PUBLIC_CHAIN_TYPE": "Testnet",
                "PORT": "3000",
                "NEXT_PUBLIC_GRAPHQL_URL": "/v1/graphql",
                "NEXT_PUBLIC_GRAPHQL_WS": "/v1/graphql",
                "NEXT_PUBLIC_RPC_WEBSOCKET": "/websocket",
                "NEXT_PUBLIC_HASURA_ADMIN_SECRET": "myadminsecretkey",
            },
            ports={
                "ui": PortSpec(number=3000, transport_protocol="TCP", wait=None)
            }
        )
    )

    return big_dipper_service



def launch_nginx(plan, big_dipper_service, hasura_service, node_service, chain_name):
    big_dipper_ip = big_dipper_service.ip_address
    big_dipper_port = big_dipper_service.ports["ui"].number
    node_ip = node_service.ip_address
    node_rpc_port = node_service.ports["rpc"].number
    hasura_ip = hasura_service.ip_address
    hasura_port = hasura_service.ports["graphql"].number

    nginx_config_data = {
        "NodeIP": node_ip,
        "NodePort": node_rpc_port,
        "BdIP": big_dipper_ip,
        "BdPort": big_dipper_port,
        "HasuraIP": hasura_ip,
        "HasuraPort": hasura_port
    }
    nginx_config_artifact = plan.render_templates(
        config = {
            "nginx.conf": struct(
                template = read_file("templates/nginx.conf.tmpl"),
                data = nginx_config_data
            )
        },
        name="{}-nginx-config".format(chain_name)
    )

    plan.add_service(
        name="{}-block-explorer".format(chain_name),
        config=ServiceConfig(
            image="nginx:latest",
            files={
                "/etc/nginx": nginx_config_artifact
            },
            ports={
                "http": PortSpec(number=80, transport_protocol="TCP", application_protocol="http", wait=None)
            },
        )
    )
