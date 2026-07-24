# Licensing: why a self-hosted Sentry template is fine under the FSL

Short version: **publishing a Railway template that lets people deploy Sentry into
their own account for their own error tracking is a Permitted Purpose under
Sentry's license. It is not a Competing Use.** This document records the reasoning
and the primary sources, so the position is auditable rather than a hand-wave.

## What license Sentry uses

Sentry's code (and this self-hosted packaging) is under the **Functional Source
License, version 1.1, Apache 2.0 future license** (`FSL-1.1-Apache-2.0`). It is a
"fair source" license: source-available, permissive for almost everything, with a
single anti-free-riding restriction, and it **converts to Apache 2.0 two years
after each version's release**.

- Sentry `LICENSE.md`: https://github.com/getsentry/sentry/blob/master/LICENSE.md
- FSL home + rationale: https://fsl.software/
- Announcement: https://techcrunch.com/2023/11/20/with-functional-source-license-sentry-wants-to-grant-developers-freedom-without-harmful-free-riding/

## The two definitions that decide it (quoted verbatim from the FSL)

**Permitted Purpose** — "any purpose other than a Competing Use." The license
lists examples of permitted use, the first being:

> using the Software: (1) for your internal use and access; (2) for non-commercial
> education; (3) for non-commercial research; and (4) in connection with
> professional services that you provide to a licensee using the Software.

**Competing Use** — "making the Software available to others in a commercial
product or service that:

> (1) substitutes for the Software; (2) substitutes for any other product or
> service we offer using the Software that exists as of the date we make the
> Software available; or (3) offers the same or substantially similar
> functionality as the Software."

So the entire restriction is aimed at one thing: **you cannot take Sentry's code
and run it as a competing hosted service for other people.**

## Why this template is a Permitted Purpose, not a Competing Use

A Railway template is a **deployment recipe**, not a service:

1. **We never operate Sentry for anyone.** The template is config + service
   definitions. Each user clicks "Deploy," and Sentry runs **in their own Railway
   account, on their own resources, for their own internal use** — the textbook
   Permitted Purpose ("for your internal use and access"). Nobody is "making the
   Software available to others in a commercial product or service."

2. **No substitution for Sentry's offering.** We are not selling access to a
   hosted Sentry. There is no product or service being offered *using* Sentry's
   code. The template is inert until a user deploys their own instance.

3. **Redistribution is explicitly allowed**, with one easy condition the license
   spells out:

   > "The Terms and Conditions apply to all copies, modifications and derivatives
   > of the Software. If you redistribute any copies, modifications or derivatives
   > of the Software, you must include a copy of or a link to these Terms and
   > Conditions and not remove any copyright notices provided in or with the
   > Software."

   This repo keeps upstream's `LICENSE.md` intact and adds nothing that strips a
   notice, so the redistribution condition is met. (In practice the template
   pulls Sentry's **prebuilt images** rather than forking source, which makes this
   even cleaner.)

4. **Sentry officially packages and encourages self-hosting.** This repo is based
   on `getsentry/self-hosted`, described upstream as "Sentry, feature-complete and
   packaged up for low-volume deployments and proofs-of-concept." Sentry's own
   docs say you can deploy it anywhere, "even inside an enterprise ecosystem." A
   Railway one-click is just a nicer front door to the deployment Sentry already
   ships.
   - https://github.com/getsentry/self-hosted
   - https://develop.sentry.dev/self-hosted/

## The one constraint, and who it lands on

The FSL restriction targets **commercial resale / competition, and that risk sits
with the end user, not with the template author.** If someone deploys this template
and then **resells Sentry-as-a-service to third parties**, *they* would breach the
FSL. The template itself does not, as long as it is not marketed as a hosted Sentry
offering. We therefore:

- describe it as a way to **self-host your own Sentry**, never as "hosted Sentry";
- do not add any "we run it for you" / multi-tenant-resale layer.

## The "internal use appears in both lists" question

Someone raised that self-hosting seems to appear as both a Permitted Purpose and,
arguably, a Competing Use (`getsentry/fsl.software` issue #13). The resolution in
practice is unambiguous from Sentry's own conduct and wording: **internal
self-hosting is exactly the use they package and encourage**; the Competing Use
clause bites only when you make Sentry *available to others* as a commercial
product/service. Running your own instance is not that.

- https://github.com/getsentry/fsl.software/issues/13

## Trademark (separate from the copyright license)

Copyright license ≠ trademark. Using the name "Sentry" **descriptively** — e.g.
"Self-hosted Sentry on Railway" — is nominative use: allowed, because it refers to
the actual product. To stay clean:

- name the template descriptively; do **not** imply it is official or endorsed;
- do not use Sentry's logo in a way that suggests an official Sentry product;
- mark it a **community / unofficial** template (Railway's convention anyway).

## Bottom line

- License: `FSL-1.1-Apache-2.0`. Self-hosting for your own use is a **Permitted
  Purpose**. ✅
- A deploy template for others to self-host **is not** a Competing Use. ✅
- Redistribution is allowed with notices preserved (we preserve them). ✅
- Sentry actively supports self-hosting. ✅
- Only line not to cross: don't operate/sell it as a hosted Sentry service, and
  keep the naming nominative + unofficial.

_Not legal advice; this is an engineering-level reading of the license text and
Sentry's public position, recorded so the decision is traceable._
