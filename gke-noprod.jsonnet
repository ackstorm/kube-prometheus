local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') + 
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'observability',
        platform: 'eks'
      },
      prometheus+: {
        resources: {},
        namespaces: [],
        replicas: 1,
        enableFeatures: ["memory-snapshot-on-shutdown", "remote-write-receiver"],
        thanos: true,
        retention: "6h",
      },
      alertmanager+: {
        resources: {},
      },
      blackboxExporter+: {
        resources: {},
      },
      grafana+: {
        resources: {},
      },
      kubeStateMetrics+: {
        resources: {},
      },
      nodeExporter+: {
        resources: {},
      },
      prometheusAdapter+: {
        resources: {},
      },
      prometheusOperator+: {
        resources: {},
      },
    },
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              containers: [
                if x.name == "kube-state-metrics"
                then x { args+: [
                  "--metric-labels-allowlist=nodes=[*]" # Extract all labels from node
                  ] 
                }
                else x
                for x in super.containers
              ]
            }
          }
        }
      }
    },
    alertmanager+: {
      secret: {}, # Do not generate alertmanager config
      podDisruptionBudget: {}, # Reduce replicas to 1 and disable PDB
      alertmanager+: {
        spec+: {
          replicas: 1,
          secrets: ["observability-basic-auth"],
          externalUrl: "https://${CLUSTER_INFO_MONITORING_URL}/alertmanager",
        }
      }
    },
    prometheus+: {
      podDisruptionBudget: {}, # Reduce replicas to 1 and disable PDB
      prometheus+: {
        spec+: {
          enableAdminAPI: false,
          retention: "12h",
          externalUrl: "https://${CLUSTER_INFO_MONITORING_URL}/prometheus",
          additionalScrapeConfigs: {
            name: "additional-scrape-configs",
            key: "additional-scrape-configs-secret.yaml",
          },
          additionalAlertRelabelConfigs: {
            name: "additional-relabel-configs",
            key: "additional-relabel-configs-secret.yaml",
          },
          additionalAlertManagerConfigs: {
            name: "additional-alertmanager-config",
            key: "additional-alertmanager-config-secret.yaml",
          },
          externalLabels: {
            cluster: "${CLUSTER_INFO_PLATFORM_NAME}-${CLUSTER_INFO_ENVIRONMENT}",
            env: "${CLUSTER_INFO_ENVIRONMENT}",
          },
          thanos: {
            version: "v0.30.2",
            objectStorageConfig: {
              key: "thanos-object-store-config-secret.yaml",
              name: "thanos-object-store-config",
            },
          },
          containers+: [{
              name: 'prometheus',
              startupProbe+: {
                failureThreshold: 120 # Extend recovery time for WAL
              }
          }]
        }
      }
    }
  };

{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) }
