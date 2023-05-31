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
      }
    }
  };

#{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{
  ['alertmanager-' + name]: kp.alertmanager[name]
  for name in std.filter((function(name) name == 'prometheusRule'), std.objectFields(kp.alertmanager))
} +
{
  ['blackbox-exporter-' + name]: kp.blackboxExporter[name]
  for name in std.filter((function(name) name == 'prometheusRule'), std.objectFields(kp.blackboxExporter))
} +
{
  ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name]
  for name in std.filter((function(name) name == 'prometheusRule'), std.objectFields(kp.kubeStateMetrics))
} +
{
  ['node-exporter-' + name]: kp.nodeExporter[name]
  for name in std.filter((function(name) name == 'prometheusRule'), std.objectFields(kp.nodeExporter))
} +
{
  ['kubernetes-' + name]: kp.kubernetesControlPlane[name]
  for name in std.filter((function(name) name == 'prometheusRule' || name == 'prometheusRuleAwsVpcCni'), std.objectFields(kp.kubernetesControlPlane))
} +
{
  ['prometheus-' + name]: kp.prometheus[name]
  for name in std.filter((function(name) name == 'prometheusRule'), std.objectFields(kp.prometheus))
}
