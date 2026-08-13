# HELIOS MCP Server — Evaluation

Eleven read-only, single-answer questions for evaluating whether an LLM can drive the
HELIOS MCP server (per the MCP builder evaluation methodology). Every question is
answerable using only non-destructive tools (`helios_ai_status`, `helios_providers_list`,
`helios_task_routing_get`, `helios_infra_validate`, `helios_foundry_agent_list`) against
a fresh checkout with **no provider keys configured**, so answers are stable. Verify answers after config changes —
they are tied to `config/aihub.json`.

Run: point an MCP-capable agent at the server (see CLIENT_SETUP.md), ask each question,
and string-compare the final answer.

```xml
<evaluation>
  <qa_pair>
    <question>How many providers in total does the HELIOS hub register, counting both API providers and CLI agents?</question>
    <answer>11</answer>
  </qa_pair>
  <qa_pair>
    <question>Which provider is the FIRST entry in the default routing chain?</question>
    <answer>azure-openai</answer>
  </qa_pair>
  <qa_pair>
    <question>For the code_review task type, which provider is primary?</question>
    <answer>anthropic</answer>
  </qa_pair>
  <qa_pair>
    <question>Which single provider handles the agent_fleet_dispatch task type?</question>
    <answer>hermes</answer>
  </qa_pair>
  <qa_pair>
    <question>Which task type routes exclusively to the local ollama provider?</question>
    <answer>offline</answer>
  </qa_pair>
  <qa_pair>
    <question>What environment variable does the status output tell you to set to configure the anthropic provider?</question>
    <answer>ANTHROPIC_API_KEY</answer>
  </qa_pair>
  <qa_pair>
    <question>What is the default model configured for the ollama provider?</question>
    <answer>llama3.2</answer>
  </qa_pair>
  <qa_pair>
    <question>How many CLI-kind agents does the provider list contain?</question>
    <answer>5</answer>
  </qa_pair>
  <qa_pair>
    <question>In the code_generation chain, which provider comes immediately after codex?</question>
    <answer>openai</answer>
  </qa_pair>
  <qa_pair>
    <question>Does infra/main.bicep compile cleanly according to helios_infra_validate (yes/no)?</question>
    <answer>yes</answer>
  </qa_pair>
  <qa_pair>
    <question>According to helios_foundry_agent_list, which environment variable must be set before Foundry agents can be listed?</question>
    <answer>AZURE_FOUNDRY_PROJECT_ENDPOINT</answer>
  </qa_pair>
</evaluation>
```
