# The fleet-deploy notice of one requests.jsonl record, posted by
# fleet-deploy-notify. A refused target that is not a machine is shown as
# received, quoted as the request command quotes it in the reason.
"\(.outcome): \(.requester) asked to deploy \(.machine // (.target | if . == null then "?" else tojson end)) at \(.commit // "main") (session \(.session // "none")): \(.reason)"
