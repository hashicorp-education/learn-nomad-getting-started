job "pytechco-web" {
  datacenters = ["dc1"]
  type = "service"

  group "ptc-web" {
    count = 1
    network {
      port "web" {
        static = 5000
      }
    }

    service {
      name = "ptc-web-svc"
      port = "web"
      provider = "nomad"
    }

    task "ptc-web-task" {
      template {
                data        = <<EOH
{{ range nomadService "redis-svc" }}
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}
FLASK_HOST=0.0.0.0
REFRESH_INTERVAL=500
{{ end }}
EOH
                destination = "local/env.txt"
                env         = true
            }

      driver = "docker"

      config {
        image = "arussohashi/ptc-web:latest"
        ports = ["web"]
      }
    }
  }
}

# Once deployed, use the following command to get the public URL for the webapp:
# nomad node status -verbose $(nomad job allocs pytechco-web | grep -i running | awk '{print $2}') | grep -i public-ipv4 | awk -F "=" '{print $2}' | xargs | awk '{print "http://"$1":5000"}'