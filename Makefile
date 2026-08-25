# Elephant Orchestration Makefile
# Routines for validation, deployment, and integration testing

SHELL := /bin/bash
CRM_DIR := residential-jax-crm
PIPELINE_DIR := oracle-property-intelligence-platform-pipeline-duval-fl
CRM_URL := https://feature-003-residential-jax-crm.d2nys96ft16522.amplifyapp.com
API_URL := https://42trwtmqqe.execute-api.us-east-2.amazonaws.com
EC2_ID := i-00bb59df78fecdfdd
REGION := us-east-2
AMPLIFY_APP := d2nys96ft16522
AMPLIFY_BRANCH := feature/003-residential-jax-crm

# --- CRM Deployment ---

crm-deploy-api: ## Deploy CRM API via CDK
	make -C $(CRM_DIR) deploy-api

crm-deploy-web: ## Trigger Amplify build for CRM frontend
	make -C $(CRM_DIR) deploy-web

crm-amplify-status: ## Check Amplify build status
	@aws amplify list-jobs \
		--app-id $(AMPLIFY_APP) \
		--branch-name $(AMPLIFY_BRANCH) \
		--region $(REGION) \
		--max-items 1 \
		--query 'jobSummaries[0].{status:status,startTime:startTime,endTime:endTime}' \
		--output table

crm-amplify-wait: ## Poll Amplify build until done (max 10 min)
	@for i in $$(seq 1 20); do \
		STATUS=$$(aws amplify list-jobs --app-id $(AMPLIFY_APP) --branch-name $(AMPLIFY_BRANCH) --region $(REGION) --max-items 1 --query 'jobSummaries[0].status' --output text 2>/dev/null); \
		echo "$$(date +%H:%M:%S) Amplify: $$STATUS"; \
		if [ "$$STATUS" = "SUCCEED" ] || [ "$$STATUS" = "FAILED" ]; then break; fi; \
		sleep 30; \
	done

# --- Pipeline EC2 ---

ec2-cmd: ## Run a command on EC2 via SSM. Usage: make ec2-cmd CMD="cat /opt/app/.env"
	@CMD_ID=$$(aws ssm send-command \
		--instance-ids $(EC2_ID) \
		--document-name "AWS-RunShellScript" \
		--parameters "commands=[\"$(CMD)\"]" \
		--region $(REGION) \
		--query 'Command.CommandId' --output text); \
	sleep 3; \
	aws ssm get-command-invocation \
		--command-id $$CMD_ID \
		--instance-id $(EC2_ID) \
		--region $(REGION) \
		--query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
		--output json

ec2-env-grep: ## Grep pipeline .env for a pattern. Usage: make ec2-env-grep PAT=WEBHOOK
	@$(MAKE) ec2-cmd CMD="grep -i '$(PAT)' /opt/app/.env || echo 'not found'"

ec2-docker-ps: ## List running containers on EC2
	@$(MAKE) ec2-cmd CMD="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# --- Webhook Testing ---

WEBHOOK_SECRET := 406f09cb3cd287b2787afa7f6e903752fa61a07740f6e89781f006b51279f659

webhook-test: ## Send a test webhook to CRM with proper HMAC
	@EVENT_ID=$$(python3 -c "import uuid; print(uuid.uuid4())"); \
	RUN_ID=$$(python3 -c "import uuid; print(uuid.uuid4())"); \
	BODY="{\"event_id\":\"$$EVENT_ID\",\"event_type\":\"artifact.published\",\"county\":\"duval\",\"run_id\":\"$$RUN_ID\",\"ipns_pointer\":\"k51qzi5uqu5dggq0h9xylfc0kr0kpw7i4zcacnfrymz9sjv7mpeze4femaujcz\",\"artifact_cid\":\"QmRpByZciNmrteH7f8FGY7MRN8JXwJKqtaM51ifdeA9HfS\",\"timestamp\":\"$$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"delta\":{\"new_count\":3,\"updated_count\":1,\"removed_count\":0,\"new_parcel_ids\":[\"000341 0000\",\"000436 0110\",\"000477 0100\"],\"updated_parcel_ids\":[\"000722 0000\"],\"removed_parcel_ids\":[]}}"; \
	SIGNATURE=$$(echo -n "$$BODY" | openssl dgst -sha256 -hmac "$(WEBHOOK_SECRET)" | awk '{print $$2}'); \
	curl -s -X POST $(API_URL)/webhook/pipeline \
		-H "Content-Type: application/json" \
		-H "X-Event-Id: $$EVENT_ID" \
		-H "X-Webhook-Signature: $$SIGNATURE" \
		-d "$$BODY" | python3 -m json.tool

# --- Validation ---

crm-api-health: ## Check CRM API is responding
	@curl -s $(API_URL)/notifications.list 2>&1 | head -80

crm-webhook-health: ## Check webhook endpoint responds to unsigned POST
	@curl -s -X POST $(API_URL)/webhook/pipeline -H "Content-Type: application/json" -d '{}' 2>&1

# --- Lambda Logs ---

crm-logs-api: ## Tail CRM API Lambda logs
	aws logs tail /aws/lambda/ResidentialCrmStack-CrmApiHandler6254E325-oVMuKI8uVoh5 --since 5m --format short --region $(REGION)

crm-logs-webhook: ## Tail CRM webhook Lambda logs
	aws logs tail /aws/lambda/ResidentialCrmStack-CrmWebhookHandler1EB0F4C4-fAbdYDVA42vz --since 5m --format short --region $(REGION)

pipeline-logs: ## Tail pipeline Lambda logs
	aws logs tail /aws/lambda/oracle-pipeline-duval-agent --since 5m --format short --region $(REGION)

# --- Git ---

crm-push: ## Push CRM repo
	git -C $(CRM_DIR) push origin $(AMPLIFY_BRANCH)

crm-status: ## Git status of CRM repo
	git -C $(CRM_DIR) status

pipeline-status: ## Git status of pipeline repo
	git -C $(PIPELINE_DIR) status

AGENT_TASKS_DIR := /private/tmp/claude-501/-Users-trasgofurioso-Code-elephant/e85f390d-9561-4388-91cf-a35552a6ec81/tasks

# --- Agent Monitoring ---

agent-check: ## Check if an agent output file is done. Usage: make agent-check ID=abc123
	@FILE=$(AGENT_TASKS_DIR)/$(ID).output; \
	if [ ! -f "$$FILE" ]; then echo "No output file for $(ID)"; exit 0; fi; \
	SIZE=$$(wc -c < "$$FILE"); \
	DONE=$$(grep -c '"stop_reason":"end_turn"' "$$FILE" 2>/dev/null || echo 0); \
	echo "Agent $(ID): $${SIZE}B, end_turn=$${DONE}"

agent-tail: ## Show last result text from agent. Usage: make agent-tail ID=abc123
	@python3 -c "\
	import json, sys; \
	data = open('$(AGENT_TASKS_DIR)/$(ID).output').read(); \
	texts = []; \
	for line in data.strip().split('\n'): \
	    try: \
	        obj = json.loads(line); \
	        c = obj.get('message',{}).get('content',[]); \
	        for b in (c if isinstance(c,list) else []): \
	            if isinstance(b,dict) and b.get('type')=='text' and len(b.get('text',''))>100: texts.append(b['text']); \
	    except: pass \
	; print(texts[-1][:3000] if texts else 'No text output yet')"

agent-list: ## List all agent output files with sizes
	@ls -lh $(AGENT_TASKS_DIR)/*.output 2>/dev/null | awk '{print $$NF, $$5}'

# --- Help ---

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
.PHONY: help
