job "pytechco-setup" {
  datacenters = ["dc1"]

  type = "batch"

    parameterized {
      meta_required = ["budget"]
  }

  group "ptc-setup" {
    count = 1

    task "ptc-setup-task" {

        template {
                data        = <<EOH
{{ range nomadService "redis-svc" }}
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}
{{ end }}
PTC_BUDGET={{ env "NOMAD_META_budget" }}
EOH
                destination = "local/env.txt"
                env         = true
            }
      driver = "docker"

      config {
        image = "arussohashi/ptc-setup:latest"
      }
    }
  }
}