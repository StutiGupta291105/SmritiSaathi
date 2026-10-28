# Incident response (CERT-In and DPDP)

Status: process draft. Names, phone numbers and the reporting form details marked
`[FILL IN]` must be completed by the organisation that runs the service, and the
legal timelines below must be checked against the current text before relying on
them (CERT-In Directions of 28 April 2022; Digital Personal Data Protection Act
2023 and its Rules).

## The clock

CERT-In expects reportable cyber incidents (including data breaches, data leaks
and unauthorised access to systems or data) to be reported within **6 hours of
noticing them**. The clock starts when anyone on the team notices, not when the
investigation ends. A first report with what is known is better than a late
complete one. The DPDP Act separately requires telling the Data Protection Board
and the affected people about a personal data breach; check the current Rules for
the content and the time limits.

## People

| Role | Person | Phone |
|---|---|---|
| Incident lead (decides, owns the clock) | [FILL IN] | [FILL IN] |
| Technical lead (contains and investigates) | [FILL IN] | [FILL IN] |
| Communications (CERT-In, Board, users) | [FILL IN] | [FILL IN] |
| Backup for each | [FILL IN] | [FILL IN] |

## How we notice

- `python -m app.cli verify-audit` fails (the audit log was changed or truncated).
- Spikes in audit actions: `otp_failed`, `refresh_reuse_detected`, `report_viewed`.
- Rate-limit responses (429) from one source, or a burst of OTP requests.
- Cloud alerts: unusual database access, new IAM keys, WAF blocks, error spikes.
- A report from a user, a caretaker or a doctor.

## First hour

1. **Write down the time you noticed.** That is T0. Tell the incident lead.
2. **Contain** without destroying evidence: revoke the affected credentials, rotate
   `SMRITI_SECRET_KEY` if tokens may be stolen (this signs everyone out), block the
   source address at the WAF, take the service offline if data is still leaving.
3. **Preserve**: snapshot the database and keep the application and cloud logs. Do
   not delete anything. Record `python -m app.cli audit-head`.
4. **Scope** using the audit log: which patients' data was read (`report_viewed`,
   `patient_exported`), by whom (actor ids), and when. Audit entries hold ids only.
5. **Decide**: is it reportable? When unsure, report.

## Within 6 hours of T0: CERT-In

Report to CERT-In by the channel on its website (email `incident@cert-in.org.in`
and the online form; confirm current details). Include what is known:

- date and time noticed, and date and time it began (if known)
- what happened and what systems were involved (API, database, cloud account)
- what data may be affected: phone-number hashes, names, game results, reminder
  timings, consent records (the server holds no photos, family contacts or
  medicine names)
- how many people may be affected
- what has been done to contain it
- a named contact (incident lead)

## After containment

- **Tell the Data Protection Board and affected people** as the DPDP Rules require:
  what happened, what data, what they should do, who to contact.
- **Fix the cause**, then restore from a clean state. Rotate every secret that was
  reachable.
- **Keep logs for at least 180 days, on infrastructure in India** (CERT-In
  direction). Keep system clocks synchronised with NIC or NPL time servers.
- **Review within a week**: timeline, what worked, what to change. Update this file.

## Report template

```
Noticed at (IST): ...
Began at (IST, if known): ...
Reported by / contact: ...
Summary: ...
Systems involved: ...
Data possibly affected (types and approximate number of people): ...
Contained? How: ...
Next steps and next update at: ...
```

## Drills

Run a tabletop drill twice a year: pick a scenario (leaked database snapshot;
stolen refresh tokens; a caretaker account used to read many patients) and time how
long it takes to reach a sendable CERT-In report. The target is under two hours.
