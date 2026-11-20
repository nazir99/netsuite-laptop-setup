<img src="assets/icon.svg" width="64" height="64" alt="">

# NetSuite laptop setup (Windows)

One script sets up a Windows laptop for NetSuite work:

1. Node, Java 17, Git
2. SuiteCloud CLI
3. nsq plus 13 NetSuite skills for Copilot (in `%USERPROFILE%\.copilot\skills`)
4. One new key for this laptop
5. nsq connected to the client account (read-only)
6. SDF connected with the same key, so there are no more browser logins

Run it again any time: finished steps are skipped and the skills update.

## What the client sees in NetSuite

One certificate, one integration, two rows on the M2M setup page:

| Role | Application | Used by |
|---|---|---|
| Read-only queries (Gabriel Rollano) | Gabriel Rollano read-only queries | nsq |
| Administrator or developer role | SuiteCloud Development Integration (built in) | SDF deploy |

SDF can only log in through Oracle's built-in app, and nsq must stay read-only, so this is the fewest rows possible.

## Nothing from other clients

The script downloads only public code. It makes a new key on the laptop and never copies keys, accounts or query results.
