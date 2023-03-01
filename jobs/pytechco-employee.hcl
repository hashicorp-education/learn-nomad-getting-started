job "pytechco-employee" {
  datacenters = ["dc1"]

    type = "batch"
    periodic {
        cron = "0/3 * * * * * *"
        prohibit_overlap = false
    }
  group "ptc-employee" {
    count = 1

    task "ptc-employee-task" {

        restart {
            attempts = 2
            delay    = "15s"
            interval = "10s"
            mode     = "fail"
        }

        template {
                data        = <<EOH
{{ range nomadService "redis-svc" }}
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}
PTC_EMPLOYEE_ID={{ env "NOMAD_SHORT_ALLOC_ID"}}
{{ end }}
EOH
                destination = "local/env.txt"
                env         = true
            }
      driver = "docker"

      config {
        image = "arussohashi/ptc-employee:latest"
        // args = [
        //     "--employee-type", "sales_engineer"
        // ]
      }
    }
  }
}