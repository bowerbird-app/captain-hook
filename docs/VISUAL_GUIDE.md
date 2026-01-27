# CaptainHook Visual Guide

## Overview

This visual guide provides diagrams, flowcharts, and architectural overviews to help you understand how CaptainHook processes webhooks from start to finish. Use this guide to quickly grasp the system's architecture, data flow, and component interactions.

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Webhook Processing Flow](#webhook-processing-flow)
3. [Provider Discovery](#provider-discovery)
4. [Action Discovery](#action-discovery)
5. [Signature Verification](#signature-verification)
6. [Action Execution](#action-execution)
7. [Database Schema](#database-schema)
8. [Configuration Hierarchy](#configuration-hierarchy)
9. [Directory Structure](#directory-structure)
10. [Component Interactions](#component-interactions)
11. [Request/Response Flow](#requestresponse-flow)
12. [Error Handling Flow](#error-handling-flow)

---

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CaptainHook System                           │
│                                                                       │
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐   │
│  │   Discovery    │    │   Webhook      │    │   Action       │   │
│  │   Layer        │───▶│   Processing   │───▶│   Execution    │   │
│  │                │    │   Layer        │    │   Layer        │   │
│  └────────────────┘    └────────────────┘    └────────────────┘   │
│         │                      │                      │             │
│         ▼                      ▼                      ▼             │
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐   │
│  │  Providers +   │    │  Verification  │    │  Background    │   │
│  │  Actions DB    │    │  + Validation  │    │  Jobs          │   │
│  └────────────────┘    └────────────────┘    └────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Rails Application                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Application Layer                                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  • captain_hook/ directory (providers, actions, verifiers)  │   │
│  │  • config/captain_hook.yml (global configuration)           │   │
│  │  • Custom actions inheriting from CaptainHook classes       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                 │                                     │
├─────────────────────────────────┼─────────────────────────────────────┤
│                                 ▼                                     │
│  CaptainHook Engine                                                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Controllers:                                                │   │
│  │    • IncomingController - Receives webhooks                 │   │
│  │    • Admin Controllers - Provider/action management         │   │
│  │                                                              │   │
│  │  Models:                                                     │   │
│  │    • Provider - Provider configuration & database           │   │
│  │    • IncomingEvent - Webhook event records                  │   │
│  │    • Action - Action definitions                            │   │
│  │    • IncomingEventAction - Execution tracking               │   │
│  │                                                              │   │
│  │  Services:                                                   │   │
│  │    • ProviderDiscovery - Find providers in filesystem       │   │
│  │    • ActionDiscovery - Find action classes                  │   │
│  │    • ProviderSync - Sync providers to database              │   │
│  │    • ActionSync - Sync actions to database                  │   │
│  │    • ActionLookup - Find actions for events                 │   │
│  │                                                              │   │
│  │  Verifiers:                                                  │   │
│  │    • Base - Base verifier class                             │   │
│  │    • Stripe - Built-in Stripe verifier                      │   │
│  │                                                              │   │
│  │  Jobs:                                                       │   │
│  │    • IncomingActionJob - Execute actions asynchronously     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                 │                                     │
├─────────────────────────────────┼─────────────────────────────────────┤
│                                 ▼                                     │
│  Database (PostgreSQL/MySQL/SQLite)                                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Tables:                                                     │   │
│  │    • captain_hook_providers                                 │   │
│  │    • captain_hook_incoming_events                           │   │
│  │    • captain_hook_actions                                   │   │
│  │    • captain_hook_incoming_event_actions                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Webhook Processing Flow

### Complete Flow (Start to Finish)

```
┌─────────────┐
│   Webhook   │
│  Provider   │
│ (e.g. Stripe)│
└──────┬──────┘
       │
       │ POST /captain_hook/:provider/:token
       │ Headers: Stripe-Signature, Content-Type
       │ Body: {"id":"evt_123","type":"payment.succeeded",...}
       ▼
┌──────────────────────────────────────────────────────────────────┐
│                    IncomingController#create                      │
└──────────────────────────────────────────────────────────────────┘
       │
       ├─▶ 1. Validate Provider
       │      ├─ Find Provider by name
       │      ├─ Check if active
       │      └─ Load ProviderConfig
       │
       ├─▶ 2. Verify Token (Constant-time comparison)
       │      └─ secure_compare(provider.token, params[:token])
       │
       ├─▶ 3. Check Rate Limiting
       │      ├─ Get rate limit from config
       │      ├─ Check Redis/cache for current count
       │      └─ Increment or reject (429 Too Many Requests)
       │
       ├─▶ 4. Check Payload Size
       │      ├─ Get max size from config
       │      └─ Compare request.raw_post.bytesize
       │
       ├─▶ 5. Verify Signature
       │      ├─ Load verifier instance
       │      ├─ Extract raw payload (request.raw_post)
       │      ├─ Extract headers
       │      └─ Call verifier.verify_signature(...)
       │
       ├─▶ 6. Parse JSON Payload
       │      └─ JSON.parse(raw_payload)
       │
       ├─▶ 7. Extract Event Metadata
       │      ├─ verifier.extract_event_id(payload)
       │      ├─ verifier.extract_event_type(payload)
       │      └─ verifier.extract_timestamp(headers)
       │
       ├─▶ 8. Validate Timestamp (if enabled)
       │      └─ TimeWindowValidator.valid?(timestamp)
       │
       ├─▶ 9. Create/Find IncomingEvent (Idempotency)
       │      ├─ find_or_create_by_external!(
       │      │    provider: "stripe",
       │      │    external_id: "evt_123",
       │      │    ...
       │      │  )
       │      └─ Check if duplicate
       │
       ├─▶ 10. Find Matching Actions
       │       ├─ ActionLookup.find_actions_for_event(
       │       │    provider: "stripe",
       │       │    event_type: "payment.succeeded"
       │       │  )
       │       └─ Order by priority
       │
       └─▶ 11. Create IncomingEventActions
              ├─ For each action:
              │   └─ IncomingEventAction.create!(
              │        incoming_event: event,
              │        action: action,
              │        status: :pending
              │      )
              │
              └─▶ 12. Execute Actions
                     ├─ Async actions: Enqueue IncomingActionJob
                     │   └─ Sidekiq/ActiveJob processes later
                     │
                     └─ Sync actions: Execute immediately
                         └─ action_class.new.webhook_action(...)

┌─────────────┐
│  Response   │
│  201 Created│
│  or 200 OK  │
└─────────────┘
```

### Simplified Flow Diagram

```
Webhook Request
      │
      ▼
┌──────────────┐
│   Provider   │──── Active? ────▶ ❌ 403 Forbidden
│  Validation  │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│    Token     │──── Valid? ─────▶ ❌ 401 Unauthorized
│ Verification │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│ Rate Limit   │──── Within? ────▶ ❌ 429 Too Many Requests
│    Check     │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│  Payload     │──── Valid? ─────▶ ❌ 413 Content Too Large
│ Size Check   │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│  Signature   │──── Valid? ─────▶ ❌ 401 Unauthorized
│ Verification │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│   Timestamp  │──── Valid? ─────▶ ❌ 400 Bad Request
│  Validation  │
└──────┬───────┘
       │ ✅
       ▼
┌──────────────┐
│   Create     │
│ IncomingEvent│
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Find Actions │
│ & Execute    │
└──────┬───────┘
       │
       ▼
✅ 201 Created / 200 OK (Duplicate)
```

---

## Provider Discovery

### Discovery Process Flow

```
Application Boot
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│              CaptainHook::Engine Initializer                 │
└─────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│            ProviderDiscovery.new.call                        │
└─────────────────────────────────────────────────────────────┘
      │
      ├─────────────────────────────┬─────────────────────────┤
      │                             │                         │
      ▼                             ▼                         ▼
┌──────────────┐         ┌──────────────────┐    ┌──────────────────┐
│ Application  │         │   Gem A          │    │   Gem B          │
│ Providers    │         │   Providers      │    │   Providers      │
└──────┬───────┘         └────────┬─────────┘    └────────┬─────────┘
       │                          │                       │
       │ Rails.root/              │ gem_dir/              │ gem_dir/
       │ captain_hook/            │ captain_hook/         │ captain_hook/
       │                          │                       │
       └─────────┬────────────────┴───────────────────────┘
                 │
                 ▼
       ┌──────────────────────────┐
       │  For Each Subdirectory:  │
       │  • stripe/               │
       │  • github/               │
       │  • custom_api/           │
       └──────────┬───────────────┘
                  │
                  ├─▶ Look for <provider>.yml
                  │     └─ stripe/stripe.yml ✅
                  │
                  ├─▶ Load YAML Configuration
                  │     └─ Parse provider settings
                  │
                  ├─▶ Load Verifier File (if exists)
                  │     ├─ stripe/stripe.rb
                  │     └─ load verifier_file
                  │
                  ├─▶ Load Actions Directory
                  │     ├─ stripe/actions/**/*.rb
                  │     └─ load all .rb files
                  │
                  └─▶ Add to @discovered_providers
                        └─ Store: name, config, source, file
                  
                  ▼
       ┌──────────────────────────┐
       │   Deduplicate Providers  │
       │   • App > Gem A > Gem B  │
       │   • Remove duplicates    │
       │   • Warn if conflicts    │
       └──────────┬───────────────┘
                  │
                  ▼
       ┌──────────────────────────┐
       │     ProviderSync         │
       │  • Create new providers  │
       │  • Update existing       │
       │  • Generate tokens       │
       └──────────┬───────────────┘
                  │
                  ▼
       ┌──────────────────────────┐
       │  Providers Ready in DB   │
       │  + Registry              │
       └──────────────────────────┘
```

### Discovery Locations

```
Priority: Application → Gem A → Gem B

┌────────────────────────────────────────────────────────────────┐
│                 Rails.root/captain_hook/                        │
│                 (Highest Priority)                              │
│                                                                 │
│  stripe/                                                        │
│  ├── stripe.yml          ← Provider config (discovered)        │
│  ├── stripe.rb           ← Verifier (loaded)                   │
│  └── actions/                                                   │
│      ├── payment_intent_action.rb  ← Action (loaded)           │
│      └── charge_action.rb          ← Action (loaded)           │
│                                                                 │
│  github/                                                        │
│  ├── github.yml          ← Provider config                     │
│  ├── github.rb           ← Verifier                            │
│  └── actions/                                                   │
│      └── push_action.rb  ← Action                              │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼ If not found in application
┌────────────────────────────────────────────────────────────────┐
│              Gem.loaded_specs[*]/captain_hook/                 │
│              (Lower Priority)                                   │
│                                                                 │
│  payment_gem/captain_hook/                                      │
│  └── stripe/                                                    │
│      ├── stripe.yml      ← Discovered if not in app            │
│      └── actions/                                               │
│          └── subscription_action.rb                             │
└────────────────────────────────────────────────────────────────┘
```

### Deduplication Logic

```
Scenario: Same provider in multiple locations

Application: stripe/stripe.yml
Gem A:       stripe/stripe.yml  
Gem B:       stripe/stripe.yml

         ┌─────────────────┐
         │  Discovery      │
         │  Finds all 3    │
         └────────┬────────┘
                  │
                  ▼
         ┌──────────────────────────┐
         │   Deduplication          │
         │                          │
         │   1. Group by name       │
         │      └─ "stripe" → [     │
         │           app,           │
         │           gem_a,         │
         │           gem_b          │
         │         ]                │
         │                          │
         │   2. Select highest      │
         │      priority (app)      │
         │                          │
         │   3. Warn about others   │
         │      └─ ⚠️  Duplicates   │
         │         found            │
         └──────────┬───────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  Result:            │
         │  Use application    │
         │  stripe config      │
         │                     │
         │  Ignore gem A & B   │
         └─────────────────────┘
```

---

## Action Discovery

### Action Discovery Flow

```
Application Boot (After Provider Discovery)
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│              ActionDiscovery.new.call                        │
└─────────────────────────────────────────────────────────────┘
      │
      ├─▶ Scan Loaded Ruby Classes
      │     └─ ObjectSpace.each_object(Class)
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  For Each Class:                                             │
│    • Check if responds_to?(:details)                        │
│    • Check if details returns Hash with :event_type         │
│    • Extract namespace/module (e.g., Stripe::)              │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  Action Definition │
         │  {                 │
         │    class: "Stripe::PaymentAction",              │
         │    event_type: "payment_intent.succeeded",      │
         │    provider: "stripe",  ← From namespace        │
         │    priority: 100,                               │
         │    async: true,                                 │
         │    max_attempts: 3                              │
         │  }                 │
         └─────────┬──────────┘
                   │
                   ▼
         ┌────────────────────┐
         │   ActionSync       │
         │   • Create/Update  │
         │     actions in DB  │
         │   • Set active=true│
         │   • Track priority │
         └─────────┬──────────┘
                   │
                   ▼
         ┌────────────────────┐
         │ Actions Ready in DB│
         └────────────────────┘
```

### Action Class Structure

```
Action Class Anatomy:

┌──────────────────────────────────────────────────────────────┐
│  module Stripe                       ← Provider namespace    │
│    class PaymentIntentAction         ← Action class          │
│                                                               │
│      def self.details                ← Class method          │
│        {                                                      │
│          event_type: "payment_intent.succeeded", ← Required  │
│          description: "...",         ← Optional              │
│          priority: 100,              ← Optional (default 50) │
│          async: true,                ← Optional (default true)│
│          max_attempts: 3,            ← Optional (default 3)  │
│          retry_delays: [60, 300]    ← Optional              │
│        }                                                      │
│      end                                                      │
│                                                               │
│      def webhook_action(event:, payload:, metadata: {})      │
│        # Your webhook processing logic                       │
│        # Access event.provider, event.external_id, etc.      │
│        # Access payload["data"], payload["object"], etc.     │
│      end                                                      │
│                                                               │
│    end                                                        │
│  end                                                          │
└──────────────────────────────────────────────────────────────┘
```

### Action Matching Logic

```
Incoming Webhook:
  provider: "stripe"
  event_type: "payment_intent.succeeded"

         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│               ActionLookup.find_actions_for_event            │
└──────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│  Query Database:                                             │
│                                                              │
│  CaptainHook::Action                                         │
│    .where(provider: "stripe", active: true)                 │
│    .where("event_type = ? OR event_type = '*'",             │
│           "payment_intent.succeeded")                        │
│    .order(priority: :desc)                                   │
└──────────────────────────┬───────────────────────────────────┘
                           │
                           ▼
         ┌────────────────────────────────────┐
         │  Matching Actions:                 │
         │                                    │
         │  1. PaymentIntentAction            │
         │     event_type: payment_intent.*   │
         │     priority: 100                  │
         │                                    │
         │  2. AllPaymentEventsAction         │
         │     event_type: payment.*          │
         │     priority: 50                   │
         │                                    │
         │  3. UniversalWebhookAction         │
         │     event_type: *                  │
         │     priority: 10                   │
         └────────────┬───────────────────────┘
                      │
                      ▼
         ┌────────────────────────────────────┐
         │  Execute in Priority Order:        │
         │  1. Priority 100 → 50 → 10         │
         │  2. Create IncomingEventAction     │
         │  3. Execute or Enqueue             │
         └────────────────────────────────────┘
```

### Event Type Patterns

```
Pattern Matching Examples:

Exact Match:
  event_type: "payment_intent.succeeded"
  ✅ Matches: payment_intent.succeeded
  ❌ Matches: payment_intent.failed
  ❌ Matches: charge.succeeded

Wildcard (Prefix):
  event_type: "payment_intent.*"
  ✅ Matches: payment_intent.succeeded
  ✅ Matches: payment_intent.failed
  ✅ Matches: payment_intent.created
  ❌ Matches: charge.succeeded

Broader Wildcard:
  event_type: "payment.*"
  ✅ Matches: payment_intent.succeeded
  ✅ Matches: payment_method.attached
  ❌ Matches: customer.created

Universal Wildcard:
  event_type: "*"
  ✅ Matches: Everything
```

---

## Signature Verification

### Verification Flow (Stripe Example)

```
Webhook Request Arrives
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  Extract Raw Payload & Headers                              │
│    raw_payload = request.raw_post                           │
│    headers = { "Stripe-Signature" => "t=123,v1=abc" }       │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Load Verifier Instance                                     │
│    verifier = provider_config.verifier                      │
│    # => #<CaptainHook::Verifiers::Stripe>                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  verifier.verify_signature(                                 │
│    payload: raw_payload,                                    │
│    headers: headers,                                        │
│    provider_config: provider_config                         │
│  )                                                          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Stripe Verifier Logic:              │
         │                                      │
         │  1. Extract signature header         │
         │     sig = headers["Stripe-Signature"]│
         │     # "t=1234567890,v1=abc,v0=xyz"   │
         │                                      │
         │  2. Parse key-value pairs            │
         │     parsed = parse_kv_header(sig)    │
         │     timestamp = parsed["t"]          │
         │     signatures = [parsed["v1"],      │
         │                   parsed["v0"]]      │
         │                                      │
         │  3. Validate timestamp               │
         │     age = now - timestamp            │
         │     return false if age > 300        │
         │                                      │
         │  4. Generate expected signature      │
         │     signed = "#{timestamp}.#{payload}"│
         │     expected = HMAC-SHA256(          │
         │       secret, signed                 │
         │     )                                │
         │                                      │
         │  5. Constant-time comparison         │
         │     signatures.any? do |sig|         │
         │       secure_compare(sig, expected)  │
         │     end                              │
         └──────────────────┬───────────────────┘
                            │
                  ┌─────────┴──────────┐
                  │                    │
                  ▼                    ▼
            ✅ Valid            ❌ Invalid
                  │                    │
                  │                    ▼
                  │          ┌──────────────────┐
                  │          │ Log failure      │
                  │          │ Return 401       │
                  │          └──────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │  Continue Processing│
         │  • Parse JSON       │
         │  • Extract event ID │
         │  • Find actions     │
         └────────────────────┘
```

### Signature Schemes Comparison

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Common Signature Schemes                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Simple HMAC (Hex)                                               │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │  Header: X-Signature: abc123def456...                    │   │
│     │  Calculation: HMAC-SHA256(secret, payload)               │   │
│     │  Encoding: Hexadecimal                                   │   │
│     │  Providers: Shopify, Slack                               │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  2. HMAC with Prefix                                                │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │  Header: X-Hub-Signature-256: sha256=abc123...           │   │
│     │  Calculation: HMAC-SHA256(secret, payload)               │   │
│     │  Encoding: Hexadecimal with "sha256=" prefix             │   │
│     │  Providers: GitHub                                       │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  3. HMAC with Timestamp (Stripe-style)                              │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │  Header: Stripe-Signature: t=123,v1=abc,v0=xyz           │   │
│     │  Calculation: HMAC-SHA256(secret, "timestamp.payload")   │   │
│     │  Encoding: Hexadecimal in key-value format               │   │
│     │  Providers: Stripe                                       │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  4. Base64 HMAC                                                     │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │  Header: X-Signature: UDH+PZicbRU3oBP6...                │   │
│     │  Calculation: HMAC-SHA256(secret, payload)               │   │
│     │  Encoding: Base64                                        │   │
│     │  Providers: Twilio, SendGrid                             │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Action Execution

### Execution Flow

```
IncomingEvent Created
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  ActionLookup.find_actions_for_event(...)                   │
│  Returns: [Action1, Action2, Action3]                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │  For Each Action:                │
         │    Create IncomingEventAction    │
         │      status: :pending            │
         └──────────────┬───────────────────┘
                        │
                        ├─────────────┬─────────────┐
                        │             │             │
                        ▼             ▼             ▼
                   Action 1      Action 2      Action 3
                   async=true    async=false   async=true
                        │             │             │
                        ▼             ▼             ▼
              ┌──────────────┐  ┌─────────┐  ┌──────────────┐
              │   Enqueue    │  │ Execute │  │   Enqueue    │
              │     Job      │  │  Now    │  │     Job      │
              └──────┬───────┘  └────┬────┘  └──────┬───────┘
                     │               │               │
                     ▼               ▼               ▼
         ┌────────────────┐  ┌──────────────┐  ┌────────────────┐
         │ IncomingAction │  │  Call        │  │ IncomingAction │
         │ Job (Sidekiq)  │  │  webhook_    │  │ Job (Sidekiq)  │
         │                │  │  action      │  │                │
         │ Process later  │  │  immediately │  │ Process later  │
         └────────┬───────┘  └──────┬───────┘  └────────┬───────┘
              │                     │                    │
              └──────────────┬──────┴────────────────────┘
                             │
                             ▼
                  ┌────────────────────┐
                  │ Update status:     │
                  │   :processing      │
                  │   :success         │
                  │   :failed          │
                  │   :retrying        │
                  └────────────────────┘
```

### Async vs Sync Execution

```
┌────────────────────────────────────────────────────────────────┐
│                     Async Execution                             │
│                     (async: true)                               │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Webhook Request → Controller creates IncomingEventAction      │
│                    with status: :pending                        │
│                                                                 │
│  Enqueue Job → IncomingActionJob.perform_later(...)            │
│                                                                 │
│  Return 201 → Webhook provider gets immediate response         │
│                                                                 │
│  Later... → Sidekiq/ActiveJob worker picks up job             │
│             ├─ Update status to :processing                    │
│             ├─ Execute action.webhook_action(...)              │
│             ├─ Update status to :success                       │
│             └─ Or retry on failure                             │
│                                                                 │
│  Benefits:                                                      │
│    ✅ Fast response to webhook provider                        │
│    ✅ Handles slow operations (API calls, etc.)                │
│    ✅ Automatic retries on failure                             │
│    ✅ Doesn't block web process                                │
│                                                                 │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                     Sync Execution                              │
│                     (async: false)                              │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Webhook Request → Controller creates IncomingEventAction      │
│                    with status: :pending                        │
│                                                                 │
│  Execute Immediately → action.webhook_action(...)              │
│                        ├─ Update status to :processing         │
│                        ├─ Run action logic                     │
│                        └─ Update status to :success/:failed    │
│                                                                 │
│  Return 201 → After action completes                           │
│                                                                 │
│  Benefits:                                                      │
│    ✅ Immediate execution (no queue delay)                     │
│    ✅ Simpler error handling                                   │
│    ✅ No job infrastructure needed                             │
│                                                                 │
│  Drawbacks:                                                     │
│    ⚠️  Slow actions delay webhook response                     │
│    ⚠️  No automatic retries                                    │
│    ⚠️  Ties up web process                                     │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### Retry Mechanism

```
Action Execution Fails
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  Check Retry Configuration:                                 │
│    max_attempts: 3                                          │
│    retry_delays: [60, 300, 900]  # 1min, 5min, 15min       │
│    current_attempt: 1                                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │  Attempt < max_attempts?         │
         └──────────────┬───────────────────┘
                        │
                ┌───────┴────────┐
                │                │
                ▼                ▼
              Yes              No
                │                │
                │                ▼
                │       ┌─────────────────┐
                │       │  Mark as        │
                │       │  :failed        │
                │       │  (permanent)    │
                │       └─────────────────┘
                │
                ▼
         ┌──────────────────────────────────┐
         │  Calculate Delay:                │
         │    delay = retry_delays[attempt] │
         │    # 1st retry: 60s              │
         │    # 2nd retry: 300s             │
         │    # 3rd retry: 900s             │
         └──────────────┬───────────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │  Update IncomingEventAction:     │
         │    status: :retrying             │
         │    attempt: attempt + 1          │
         │    retry_at: Time.now + delay    │
         └──────────────┬───────────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │  Schedule Retry:                 │
         │    IncomingActionJob             │
         │      .set(wait: delay)           │
         │      .perform_later(...)         │
         └──────────────────────────────────┘
```

---

## Database Schema

### Entity Relationship Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Database Schema                               │
└──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────┐
│  captain_hook_providers     │
├─────────────────────────────┤
│  id (PK)                    │
│  name (unique, indexed)     │───┐
│  token (unique)             │   │
│  active (boolean)           │   │
│  rate_limit_requests        │   │
│  rate_limit_period          │   │
│  created_at                 │   │
│  updated_at                 │   │
└─────────────────────────────┘   │
                                  │
                                  │ has_many :incoming_events
                                  │ has_many :actions
                                  │
        ┌─────────────────────────┼────────────────────────────┐
        │                         │                            │
        ▼                         ▼                            ▼
┌───────────────────────┐  ┌─────────────────────────┐  ┌────────────────────┐
│ captain_hook_         │  │ captain_hook_actions    │  │ captain_hook_      │
│ incoming_events       │  ├─────────────────────────┤  │ incoming_event_    │
├───────────────────────┤  │ id (PK)                 │  │ actions            │
│ id (PK)               │  │ provider (FK)           │──┤├────────────────────┤
│ provider (FK)         │──┘ event_type              │  ││ id (PK)            │
│ external_id (indexed) │    action_class            │  ││ incoming_event_id  │──┐
│ event_type (indexed)  │──┐ priority (default 50)   │  ││ action_id          │──┤
│ payload (json)        │  │ async (default true)    │  ││ status             │  │
│ headers (json)        │  │ max_attempts (default 3)│  ││ attempt            │  │
│ metadata (json)       │  │ retry_delays (json)     │  ││ executed_at        │  │
│ status                │  │ active (default true)   │  ││ error_message      │  │
│ dedup_state           │  │ created_at              │  ││ created_at         │  │
│ request_id            │  │ updated_at              │  ││ updated_at         │  │
│ created_at            │  └─────────────────────────┘  │└────────────────────┘  │
│ updated_at            │            │                  │                        │
└───────────────────────┘            │                  │                        │
         │                           │                  │                        │
         │ has_many                  │ has_many         │ belongs_to             │
         │ :incoming_event_actions   │ :incoming_event_ │ :incoming_event        │
         │                           │  actions         │                        │
         └───────────────────────────┴──────────────────┴────────────────────────┘
                                                                │
                                                                │ belongs_to
                                                                │ :action
                                                                ▼
                                                        (links to actions)
```

### Table Descriptions

```
┌──────────────────────────────────────────────────────────────────────┐
│  captain_hook_providers                                              │
│  Stores provider configuration synced from YAML + database fields    │
├──────────────────────────────────────────────────────────────────────┤
│  • name: Provider identifier (e.g., "stripe", "github")              │
│  • token: Unique token for webhook URL                               │
│  • active: Whether provider accepts webhooks                         │
│  • rate_limit_*: Request throttling settings                         │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  captain_hook_incoming_events                                        │
│  Stores received webhook events (one record per webhook)             │
├──────────────────────────────────────────────────────────────────────┤
│  • external_id: Provider's event ID (for idempotency)                │
│  • event_type: Event type (e.g., "payment_intent.succeeded")         │
│  • payload: Full webhook JSON payload                                │
│  • headers: Request headers                                          │
│  • status: :received, :duplicate, :processed                         │
│  • dedup_state: :unique, :duplicate                                  │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  captain_hook_actions                                                │
│  Stores action definitions discovered from code                      │
├──────────────────────────────────────────────────────────────────────┤
│  • action_class: Full class name (e.g., "Stripe::PaymentAction")     │
│  • event_type: Pattern to match (e.g., "payment.*")                  │
│  • priority: Execution order (higher = first)                        │
│  • async: Execute in background job vs inline                        │
│  • max_attempts: Retry limit for failures                            │
│  • retry_delays: Array of delays between retries (seconds)           │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  captain_hook_incoming_event_actions                                 │
│  Join table tracking action execution for each webhook event         │
├──────────────────────────────────────────────────────────────────────┤
│  • status: :pending, :processing, :success, :failed, :retrying       │
│  • attempt: Current retry attempt number                             │
│  • executed_at: When action was executed                             │
│  • error_message: Error details if failed                            │
│  • One record per (incoming_event, action) pair                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Configuration Hierarchy

### Three-Tier Priority System

```
┌──────────────────────────────────────────────────────────────────────┐
│                   Configuration Resolution                            │
│                   (Highest to Lowest Priority)                        │
└──────────────────────────────────────────────────────────────────────┘

1️⃣  HIGHEST PRIORITY
┌─────────────────────────────────────────────────────────────────┐
│  config/captain_hook.yml - Provider Override                    │
│  ────────────────────────────────────────────────────────       │
│  providers:                                                     │
│    stripe:                                                      │
│      timestamp_tolerance_seconds: 600  # ← Wins!               │
│      max_payload_size_bytes: 2097152                           │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ If not found, try...
                               ▼
2️⃣  MEDIUM PRIORITY
┌─────────────────────────────────────────────────────────────────┐
│  captain_hook/stripe/stripe.yml - Provider YAML                 │
│  ────────────────────────────────────────────────────────       │
│  name: stripe                                                   │
│  timestamp_tolerance_seconds: 300  # ← Used if no override     │
│  max_payload_size_bytes: 1048576                               │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ If not found, use...
                               ▼
3️⃣  LOWEST PRIORITY
┌─────────────────────────────────────────────────────────────────┐
│  config/captain_hook.yml - Global Defaults                      │
│  ────────────────────────────────────────────────────────────   │
│  defaults:                                                      │
│    timestamp_tolerance_seconds: 300  # ← Fallback              │
│    max_payload_size_bytes: 1048576                             │
└─────────────────────────────────────────────────────────────────┘
```

### Resolution Example

```
Scenario: Resolve timestamp_tolerance_seconds for Stripe

┌─────────────────────────────────────────────────────────────────┐
│  config/captain_hook.yml                                        │
│  ───────────────────────                                        │
│  defaults:                                                      │
│    timestamp_tolerance_seconds: 300                            │
│                                                                 │
│  providers:                                                     │
│    stripe:                                                      │
│      timestamp_tolerance_seconds: 900  # ← Override present    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  captain_hook/stripe/stripe.yml                                 │
│  ───────────────────────────────                                │
│  timestamp_tolerance_seconds: 600  # ← Ignored!                 │
└─────────────────────────────────────────────────────────────────┘

Result: timestamp_tolerance_seconds = 900
        (Provider override wins)

┌─────────────────────────────────────────────────────────────────┐
│  Final ProviderConfig:                                          │
│    name: "stripe"                                               │
│    timestamp_tolerance_seconds: 900  ✅                         │
│    max_payload_size_bytes: 1048576  (from defaults)            │
│    signing_secret: ENV[STRIPE_SECRET]  (from stripe.yml)       │
└─────────────────────────────────────────────────────────────────┘
```

### Fields Using Hierarchy

```
✅ Uses Configuration Hierarchy:
   • timestamp_tolerance_seconds
   • max_payload_size_bytes

❌ Does NOT Use Hierarchy (provider YAML only):
   • name
   • display_name
   • description
   • verifier_file
   • signing_secret
   • active (if specified in YAML)
   • rate_limit_requests (if specified in YAML)
   • rate_limit_period (if specified in YAML)
```

---

## Directory Structure

### Complete Project Layout

```
Rails Application Root
│
├── captain_hook/                    ← Provider & action definitions
│   ├── stripe/
│   │   ├── stripe.yml              ← Provider config
│   │   ├── stripe.rb               ← Custom verifier (optional)
│   │   └── actions/
│   │       ├── payment_intent_action.rb
│   │       ├── charge_action.rb
│   │       └── subscriptions/
│   │           └── subscription_action.rb
│   │
│   ├── github/
│   │   ├── github.yml
│   │   ├── github.rb
│   │   └── actions/
│   │       ├── push_action.rb
│   │       └── pull_request_action.rb
│   │
│   └── custom_api/
│       ├── custom_api.yml
│       └── actions/
│           └── webhook_action.rb
│
├── config/
│   └── captain_hook.yml            ← Global configuration (optional)
│
├── app/
│   └── ... (your application code)
│
├── lib/
│   └── captain_hook/               ← Engine code (from gem)
│       ├── configuration.rb
│       ├── provider_config.rb
│       ├── verifiers/
│       │   ├── base.rb
│       │   └── stripe.rb
│       └── services/
│           ├── provider_discovery.rb
│           ├── action_discovery.rb
│           └── ...
│
└── db/
    └── migrate/
        └── captain_hook/
            ├── 20260123000001_create_captain_hook_providers.rb
            ├── 20260123000002_create_captain_hook_incoming_events.rb
            ├── 20260123000003_create_captain_hook_actions.rb
            └── 20260123000004_create_captain_hook_incoming_event_actions.rb
```

### Provider Directory Structure

```
captain_hook/<provider>/
│
├── <provider>.yml           ← REQUIRED: Provider configuration
│   Example: stripe.yml
│   Contains: name, verifier_file, signing_secret, etc.
│
├── <provider>.rb            ← OPTIONAL: Custom verifier
│   Example: stripe.rb
│   Contains: StripeVerifier class with verify_signature method
│
└── actions/                 ← OPTIONAL: Action classes
    ├── *.rb                 ← Any Ruby files are loaded
    └── subdirectories/      ← Nested directories supported
        └── *.rb

Naming Rules:
  ✅ CORRECT:
     stripe/stripe.yml
     stripe/stripe.rb
     stripe/actions/payment_action.rb

  ❌ WRONG:
     stripe/config.yml         # Must be stripe.yml
     stripe/verifier.rb        # Should be stripe.rb
     stripe_actions/           # Should be actions/
```

---

## Component Interactions

### Request Flow Through Components

```
┌──────────────┐
│   Webhook    │
│   Provider   │
└──────┬───────┘
       │ HTTP POST
       ▼
┌─────────────────────────────────────────────────────────────┐
│                 IncomingController                          │
├─────────────────────────────────────────────────────────────┤
│  • Route matching                                           │
│  • Parameter extraction                                     │
│  • Rate limiting                                            │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ├─▶ Provider ──────▶ Database
                        │   (find by name)
                        │
                        ├─▶ ProviderConfig ──▶ Configuration
                        │   (merge YAML + DB)
                        │
                        ├─▶ Verifier ──────▶ VerifierHelpers
                        │   (signature check)
                        │
                        ├─▶ IncomingEvent ──▶ Database
                        │   (create/find)
                        │
                        └─▶ ActionLookup ───▶ Database
                            (find actions)
                            │
                            ▼
         ┌──────────────────────────────────────────┐
         │   Create IncomingEventActions            │
         └───────────────┬──────────────────────────┘
                         │
                         ├─▶ Async Actions
                         │   └─▶ IncomingActionJob
                         │       └─▶ Sidekiq Queue
                         │
                         └─▶ Sync Actions
                             └─▶ Direct execution
```

### Admin UI Flow

```
Browser Request: /captain_hook/admin/providers
                        │
                        ▼
         ┌──────────────────────────────┐
         │  ProvidersController#index   │
         └──────────────┬───────────────┘
                        │
                        ├─▶ Provider.all ──────▶ Database
                        │   (get all providers)
                        │
                        └─▶ ProviderDiscovery ──▶ Filesystem
                            (get registry info)
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Render View:                        │
         │  • Provider name                     │
         │  • Active status                     │
         │  • Webhook URL with token            │
         │  • Configuration source              │
         │  • Recent events count               │
         │  • Actions count                     │
         └──────────────────────────────────────┘

Click Provider → /captain_hook/admin/providers/:id
                        │
                        ▼
         ┌──────────────────────────────┐
         │  ProvidersController#show    │
         └──────────────┬───────────────┘
                        │
                        ├─▶ Provider.find(id) ──▶ Database
                        │
                        ├─▶ provider.incoming_events.recent
                        │
                        ├─▶ provider.actions
                        │
                        └─▶ ProviderConfig
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Render Details:                     │
         │  • Full configuration                │
         │  • Verifier class                    │
         │  • Recent webhooks                   │
         │  • Associated actions                │
         │  • Edit controls                     │
         └──────────────────────────────────────┘
```

---

## Request/Response Flow

### Successful Webhook Processing

```
Time: T+0ms
┌────────────────────────────────────────────────────────┐
│  POST /captain_hook/stripe/abc123token                 │
│  Headers: Stripe-Signature: t=...,v1=...               │
│  Body: {"id":"evt_123","type":"payment.succeeded",...} │
└────────────────────────────────────────────────────────┘

Time: T+5ms
┌────────────────────────────────────────────────────────┐
│  Controller Validations:                               │
│  ✅ Provider "stripe" found and active                 │
│  ✅ Token matches                                      │
│  ✅ Rate limit not exceeded (50/100 requests)          │
│  ✅ Payload size: 1,234 bytes < 1 MB limit             │
└────────────────────────────────────────────────────────┘

Time: T+15ms
┌────────────────────────────────────────────────────────┐
│  Signature Verification:                               │
│  ✅ Stripe-Signature header present                    │
│  ✅ Timestamp within tolerance (120 seconds old)       │
│  ✅ HMAC signature matches                             │
└────────────────────────────────────────────────────────┘

Time: T+20ms
┌────────────────────────────────────────────────────────┐
│  Event Processing:                                     │
│  • Parse JSON payload                                  │
│  • Extract event ID: "evt_123"                         │
│  • Extract event type: "payment_intent.succeeded"      │
│  • Create IncomingEvent (new record)                   │
└────────────────────────────────────────────────────────┘

Time: T+30ms
┌────────────────────────────────────────────────────────┐
│  Action Lookup:                                        │
│  Found 3 matching actions:                             │
│    1. PaymentIntentAction (priority: 100, async: true) │
│    2. AllPaymentsAction (priority: 50, async: true)    │
│    3. LogAllEventsAction (priority: 10, async: false)  │
└────────────────────────────────────────────────────────┘

Time: T+35ms
┌────────────────────────────────────────────────────────┐
│  Create IncomingEventActions:                          │
│    • PaymentIntentAction → status: pending             │
│    • AllPaymentsAction → status: pending               │
│    • LogAllEventsAction → status: pending              │
└────────────────────────────────────────────────────────┘

Time: T+40ms
┌────────────────────────────────────────────────────────┐
│  Execute Actions:                                      │
│    • PaymentIntentAction → Enqueue job                 │
│    • AllPaymentsAction → Enqueue job                   │
│    • LogAllEventsAction → Execute inline               │
│      └─ Status: success (completed in 2ms)             │
└────────────────────────────────────────────────────────┘

Time: T+45ms
┌────────────────────────────────────────────────────────┐
│  Response:                                             │
│  HTTP 201 Created                                      │
│  {"id":12345,"status":"received"}                      │
└────────────────────────────────────────────────────────┘

Time: T+2000ms (2 seconds later)
┌────────────────────────────────────────────────────────┐
│  Background Job Processing:                            │
│    • Sidekiq picks up PaymentIntentAction job          │
│      ├─ Status: processing                             │
│      ├─ Execute webhook_action(...)                    │
│      └─ Status: success                                │
│                                                         │
│    • Sidekiq picks up AllPaymentsAction job            │
│      ├─ Status: processing                             │
│      ├─ Execute webhook_action(...)                    │
│      └─ Status: success                                │
└────────────────────────────────────────────────────────┘
```

### Duplicate Webhook Handling

```
Time: T+0ms (First Request)
┌────────────────────────────────────────────────────────┐
│  POST /captain_hook/stripe/abc123                      │
│  Body: {"id":"evt_123","type":"payment.succeeded"}     │
└────────────────────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────────────────────┐
│  Create IncomingEvent:                                 │
│    provider: "stripe"                                  │
│    external_id: "evt_123"                              │
│    status: :received                                   │
│    dedup_state: :unique                                │
└────────────────────────────────────────────────────────┘
       │
       ▼
✅ 201 Created - Actions executed


Time: T+5000ms (5 seconds later - Second Request)
┌────────────────────────────────────────────────────────┐
│  POST /captain_hook/stripe/abc123                      │
│  Body: {"id":"evt_123","type":"payment.succeeded"}     │
│  (Same external_id!)                                   │
└────────────────────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────────────────────┐
│  find_or_create_by_external!:                          │
│    Finds existing record with external_id="evt_123"    │
│    Returns existing IncomingEvent                      │
│    previously_new_record? = false                      │
└────────────────────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────────────────────┐
│  Mark as Duplicate:                                    │
│    dedup_state: :duplicate                             │
│    Skip action creation                                │
└────────────────────────────────────────────────────────┘
       │
       ▼
✅ 200 OK - {"id":12345,"status":"duplicate"}
   (No actions executed)
```

---

## Error Handling Flow

### Error Response Matrix

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Error Scenarios                                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Provider Not Found                                                   │
│  ├─ Condition: Provider name doesn't exist                           │
│  ├─ Response: 404 Not Found                                          │
│  └─ Body: {"error":"Unknown provider"}                               │
│                                                                       │
│  Provider Inactive                                                    │
│  ├─ Condition: Provider.active = false                               │
│  ├─ Response: 403 Forbidden                                          │
│  └─ Body: {"error":"Provider is inactive"}                           │
│                                                                       │
│  Invalid Token                                                        │
│  ├─ Condition: URL token doesn't match provider.token                │
│  ├─ Response: 401 Unauthorized                                       │
│  └─ Body: {"error":"Invalid token"}                                  │
│                                                                       │
│  Rate Limit Exceeded                                                  │
│  ├─ Condition: Too many requests in time window                      │
│  ├─ Response: 429 Too Many Requests                                  │
│  └─ Body: {"error":"Rate limit exceeded"}                            │
│                                                                       │
│  Payload Too Large                                                    │
│  ├─ Condition: Body size > max_payload_size_bytes                    │
│  ├─ Response: 413 Content Too Large                                  │
│  └─ Body: {"error":"Payload too large"}                              │
│                                                                       │
│  Invalid Signature                                                    │
│  ├─ Condition: Signature verification fails                          │
│  ├─ Response: 401 Unauthorized                                       │
│  └─ Body: {"error":"Invalid signature"}                              │
│                                                                       │
│  Invalid JSON                                                         │
│  ├─ Condition: JSON.parse raises error                               │
│  ├─ Response: 400 Bad Request                                        │
│  └─ Body: {"error":"Invalid JSON"}                                   │
│                                                                       │
│  Timestamp Expired                                                    │
│  ├─ Condition: Timestamp outside tolerance window                    │
│  ├─ Response: 400 Bad Request                                        │
│  └─ Body: {"error":"Timestamp outside tolerance window"}             │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### Action Failure Handling

```
Action Execution Fails
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│  Exception Raised in webhook_action(...)                │
│    StandardError: "API connection timeout"              │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────┐
         │  IncomingActionJob#perform   │
         │  rescue => e                 │
         └──────────────┬───────────────┘
                        │
                        ▼
         ┌──────────────────────────────────────┐
         │  Update IncomingEventAction:         │
         │    status: :failed                   │
         │    error_message: e.message          │
         │    attempt: 1                        │
         └──────────────┬───────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────┐
         │  Check Retry Policy:         │
         │    max_attempts: 3           │
         │    current_attempt: 1        │
         └──────────────┬───────────────┘
                        │
                        ▼
         ┌──────────────────────────────────────┐
         │  Schedule Retry:                     │
         │    status: :retrying                 │
         │    retry_at: Time.now + 60           │
         │    IncomingActionJob                 │
         │      .set(wait: 60.seconds)          │
         │      .perform_later(...)             │
         └──────────────┬───────────────────────┘
                        │
        ┌───────────────┴────────────────┐
        │                                │
        ▼                                ▼
  Retry 1 (60s)                   Retry 2 (300s)
  Success ✅                       Success ✅
        │                                │
        ▼                                │
  status: :success                       │
                                         │
                                         ▼
                                    Retry 3 (900s)
                                    Fails ❌
                                         │
                                         ▼
                            ┌────────────────────────────┐
                            │  Max Attempts Reached:     │
                            │    status: :failed         │
                            │    (permanent)             │
                            │  No more retries           │
                            └────────────────────────────┘
```

---

## Summary Diagrams

### Complete System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CaptainHook System Flow                          │
└─────────────────────────────────────────────────────────────────────┘

External                Application Boot              Runtime
Provider                                              Webhook Processing
   │                          │                             │
   │                          │                             │
   │                          ▼                             │
   │              ┌────────────────────────┐               │
   │              │  Provider Discovery    │               │
   │              │  • Scan captain_hook/  │               │
   │              │  • Load YAML configs   │               │
   │              │  • Load verifiers      │               │
   │              │  • Sync to database    │               │
   │              └───────────┬────────────┘               │
   │                          │                             │
   │                          ▼                             │
   │              ┌────────────────────────┐               │
   │              │  Action Discovery      │               │
   │              │  • Find action classes │               │
   │              │  • Extract metadata    │               │
   │              │  • Sync to database    │               │
   │              └───────────┬────────────┘               │
   │                          │                             │
   │                          ▼                             │
   │              ┌────────────────────────┐               │
   │              │   System Ready         │               │
   │              │   • Providers loaded   │◀──────────────┤
   │              │   • Actions registered │               │
   │              │   • Routes mounted     │               │
   │              └────────────────────────┘               │
   │                                                        │
   │                                                        │
   ├────────────────────────────────────────────────────────▶
   │  POST /captain_hook/:provider/:token
   │
   │                                        ┌──────────────────────┐
   │                                        │  Validate & Verify   │
   │                                        │  • Provider active   │
   │                                        │  • Token valid       │
   │                                        │  • Rate limit OK     │
   │                                        │  • Signature valid   │
   │                                        └──────────┬───────────┘
   │                                                   │
   │                                                   ▼
   │                                        ┌──────────────────────┐
   │                                        │  Create Event        │
   │                                        │  • Parse payload     │
   │                                        │  • Extract metadata  │
   │                                        │  • Save to DB        │
   │                                        └──────────┬───────────┘
   │                                                   │
   │                                                   ▼
   │                                        ┌──────────────────────┐
   │                                        │  Execute Actions     │
   │                                        │  • Find matching     │
   │                                        │  • Create records    │
   │                                        │  • Enqueue/execute   │
   │                                        └──────────┬───────────┘
   │                                                   │
   │◀──────────────────────────────────────────────────┘
   │  201 Created
   │
   ▼
[Provider receives
 acknowledgment]
```

---

## Quick Reference

### HTTP Status Codes

| Code | Meaning | When |
|------|---------|------|
| 200 | OK | Duplicate webhook received |
| 201 | Created | New webhook processed successfully |
| 400 | Bad Request | Invalid JSON or expired timestamp |
| 401 | Unauthorized | Invalid token or signature |
| 403 | Forbidden | Provider inactive |
| 404 | Not Found | Provider doesn't exist |
| 413 | Content Too Large | Payload exceeds size limit |
| 429 | Too Many Requests | Rate limit exceeded |

### File Locations

| Component | Location |
|-----------|----------|
| Providers | `captain_hook/<provider>/<provider>.yml` |
| Verifiers | `captain_hook/<provider>/<provider>.rb` |
| Actions | `captain_hook/<provider>/actions/*.rb` |
| Global Config | `config/captain_hook.yml` |
| Migrations | `db/migrate/captain_hook/*.rb` |
| Admin UI | `/captain_hook/admin` |
| Webhook URL | `/captain_hook/:provider/:token` |

### Key Classes

| Class | Purpose |
|-------|---------|
| `ProviderConfig` | Provider configuration struct |
| `Provider` | Database model for providers |
| `IncomingEvent` | Database model for webhook events |
| `Action` | Database model for action definitions |
| `IncomingEventAction` | Join table for event-action execution |
| `ProviderDiscovery` | Scans filesystem for providers |
| `ActionDiscovery` | Scans code for action classes |
| `ActionLookup` | Finds actions for events |
| `IncomingController` | Receives webhooks |
| `IncomingActionJob` | Executes actions asynchronously |

---

## See Also

- [Action Discovery](ACTION_DISCOVERY.md) - Detailed action discovery documentation
- [Action Management](ACTION_MANAGEMENT.md) - Managing actions via admin UI
- [Provider Discovery](PROVIDER_DISCOVERY.md) - Provider discovery process
- [Verifiers](VERIFIERS.md) - Creating custom verifiers
- [Verifier Helpers](VERIFIER_HELPERS.md) - Security utility methods
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Complete technical documentation
