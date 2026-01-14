// src/index.ts

type Amount = { label: string; value: number; currency: string; source?: string | null };
type LabeledValue = { label: string; value: string; source: string | null };
type DetailLevel = "short" | "medium" | "long";

type LegalCitation = {
  // Prefer citations to the DOCUMENT (clause/section/page + a short quote).
  // This is reliable because it comes from OCR text.
  source_type: "document" | "external";
  source: string; // e.g., "Section 5(b)", "Page 2", "Clause: Termination", or statute name if external
  quote?: string | null; // short snippet from the document (recommended)
  url?: string | null;   // optional if external, otherwise null
};

type PartyRight = {
  right: string;                 // short label: "Right to terminate", "Right to collect rent", etc.
  details: string;               // 1–3 sentences explaining the right in plain language
  source: string | null;         // where in document, e.g. "Section 8", or null
  citations: LegalCitation[];    // usually document citations
};

type PartyBenefitsLiabilitiesPenalties = {
  party: string;
  role_title: string;            // NEW: "Landlord", "Tenant", etc; fallback to "Party 1"/"Party 2"
  benefits: string[];
  liabilities: string[];
  possible_penalties: string[];
  catches: string[];
  rights: PartyRight[];          // NEW
};

type WhoBenefitsMost = {
  party: string; // must be a party name or "Unclear"
  confidence: number; // 0..1
  reasons: string[];
};

type Drafts =
  | {
	  response_draft_short: string;
	  response_draft_medium: string;
	  response_draft_long: string;
	  questions_for_advisor: string;
	}
  | null;

type DocumentAnalyzeResponse = {
  doc_type: string;
  confidence: number;

  summary_plain: string;

  simple_english: string;

  eli5_paragraphs: [string, string];
  eli5_analogy: string;

  party_analysis: PartyBenefitsLiabilitiesPenalties[];
  who_benefits_most: WhoBenefitsMost;

  analysis_paragraphs: [string, string, string];

  key_facts: {
	parties: string[];
	dates: LabeledValue[];
	amounts: Amount[];
	obligations: string[];
	deadlines: string[];
	governing_law: string | null;
	key_points: string[];
  };

  urgency: { level: "low" | "medium" | "high"; reasons: string[] };
  next_steps: { title: string; detail: string }[];
  red_flags: string[];
  drafts: Drafts;
  limitations: string[];
  suggested_questions: string[];
};

type DocumentAnalyzeRequest = {
  text: string;
  detail_level?: DetailLevel;
  locale?: string;
  jurisdiction_hint?: string | null;
  client_context?: any;
};

type ChatMessage = { role: "system" | "user" | "assistant"; content: string };

type ChatRequest = {
  document_text: string;
  detail_level?: DetailLevel;
  messages: ChatMessage[];
};

type PDFDraft = {
  filename?: string;
  title?: string;
  sections?: { heading?: string; body?: string }[];
};

type ChatResponse = {
  reply: string;
  pdf_draft?: PDFDraft;
  limitations?: string[];
};

export interface Env {
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
}

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Access-Control-Allow-Headers": "Content-Type",
};

function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
	status,
	headers: {
	  "Content-Type": "application/json",
	  ...corsHeaders,
	  ...extraHeaders,
	},
  });
}

function safeParseJSON(text: string): any {
  const cleaned = text
	.trim()
	.replace(/^```(?:json)?/i, "")
	.replace(/```$/i, "")
	.trim();
  return JSON.parse(cleaned);
}

function normalizeDetailLevel(level?: string): DetailLevel {
  if (level === "short" || level === "medium" || level === "long") return level;
  return "medium";
}

function normalizePathname(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith("/")) return pathname.slice(0, -1);
  return pathname;
}

function buildDrafts(detailLevel: DetailLevel): Drafts {
  const short = `To whom it may concern,

I am writing regarding the document you provided. I have questions about certain terms and would like clarification in writing.

Sincerely,`;

  const medium = `To whom it may concern,

I reviewed the document you provided. I would like clarification on the obligations, deadlines, and any penalties or consequences. Please confirm the relevant sections and provide responses in writing.

Sincerely,`;

  const long = `To whom it may concern,

I reviewed the document you provided and would like clarification on several items before proceeding. Please respond in writing and reference the specific section(s) for each item:

1) The exact obligations each party must perform and when.
2) Any deadlines, notice requirements, cure periods, or escalation steps.
3) Any penalties, fees, interest, liquidated damages, or consequences for non-compliance.
4) Any limitations of liability, indemnity provisions, warranties, or disclaimers.
5) The governing law and dispute resolution process (venue, arbitration, attorneys’ fees, etc.).

Thank you.

Sincerely,`;

  const questions = `Questions to ask before signing:
- What are my key obligations and deadlines?
- What happens if I miss a deadline (fees, termination, default)?
- Are there penalties, interest, liquidated damages, or attorneys’ fees provisions?
- Are there any broad indemnity / liability clauses?
- Can any terms be negotiated (payment, termination, confidentiality)?
- What dispute resolution process applies (court, arbitration, venue)?
`;

  void detailLevel;

  return {
	response_draft_short: short,
	response_draft_medium: medium,
	response_draft_long: long,
	questions_for_advisor: questions,
  };
}

function fallbackResponse(detailLevel: DetailLevel, reason: string): DocumentAnalyzeResponse {
  const analysis_paragraphs: [string, string, string] = [
	"This appears to be a legal document that sets rules, responsibilities, and potential consequences for the parties involved.",
	"Key things to verify are who the parties are, what each side must do, what deadlines exist, and what happens if someone fails to comply.",
	"A cautious approach is to identify obligations and risks, ask for clarification, and avoid signing until unclear terms are explained.",
  ];

  return {
	doc_type: "unknown",
	confidence: 0.25,
	summary_plain: `Fallback: ${reason}`,

	simple_english:
	  "This is a legal document. It explains what each side agrees to do, what deadlines exist, and what can happen if someone does not follow the rules.",

	eli5_paragraphs: [
	  "Imagine this paper is a set of “rules for playing together.” It tells each person what they must do and what they are allowed to do. If one person doesn’t follow the rules, the paper can say what happens next.",
	  "Before you say “yes,” you want to check: (1) what you must do, (2) when you must do it, and (3) what the punishment is if you don’t. If something is confusing, it’s okay to ask questions before agreeing.",
	],
	eli5_analogy:
	  "It’s like joining a team and signing a team rules sheet: you get to play (benefits), but you must follow rules (obligations), and there might be consequences like getting benched (penalties) if you break them.",

	party_analysis: [
	  {
		party: "Party A",
		role_title: "Party 1",
		benefits: ["Clear expectations"],
		liabilities: ["May have duties, deadlines, or restrictions"],
		possible_penalties: ["Possible fees, damages, or termination if obligations are not met (depends on the document)"],
		catches: ["Some terms may be one-sided or have exceptions that reduce the benefit (depends on the document)"],
		rights: [],
	  },
	  {
		party: "Party B",
		role_title: "Party 2",
		benefits: ["Clear expectations"],
		liabilities: ["May have duties, deadlines, or restrictions"],
		possible_penalties: ["Possible fees, damages, or termination if obligations are not met (depends on the document)"],
		catches: ["Some terms may be one-sided or have exceptions that reduce the benefit (depends on the document)"],
		rights: [],
	  },
	],

	who_benefits_most: {
	  party: "Unclear",
	  confidence: 0.2,
	  reasons: ["A full model analysis is not available in fallback mode."],
	},

	analysis_paragraphs,

	key_facts: {
	  parties: [],
	  dates: [],
	  amounts: [],
	  obligations: [],
	  deadlines: [],
	  governing_law: null,
	  key_points: [],
	},

	urgency: { level: "low", reasons: [reason] },
	next_steps: [{ title: "Try again", detail: "If available, enable OpenAI analysis and re-run." }],
	red_flags: [],
	drafts: buildDrafts(detailLevel),
	limitations: ["Not legal advice.", "Fallback output."],
	suggested_questions: [
	  "What are my main obligations?",
	  "Are there deadlines or notice requirements?",
	  "What penalties or remedies apply if someone breaches?",
	  "Are there any hidden catches or one-sided clauses?",
	  "What is the governing law and dispute process?",
	],
  };
}

async function callOpenAIChat(env: Env, messages: { role: string; content: string }[]) {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("missing_api_key");

  const model = env.OPENAI_MODEL || "gpt-4o-mini";

  const resp = await fetch("https://api.openai.com/v1/chat/completions", {
	method: "POST",
	headers: {
	  Authorization: `Bearer ${apiKey}`,
	  "Content-Type": "application/json",
	},
	body: JSON.stringify({
	  model,
	  temperature: 0.2,
	  messages,
	}),
  });

  if (!resp.ok) {
	const errText = await resp.text().catch(() => "");
	const error = new Error(`openai_http_${resp.status}`);
	(error as any).status = resp.status;
	(error as any).body = errText;
	throw error;
  }

  const data = await resp.json<any>();
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) throw new Error("empty_openai_content");
  return content;
}

function userWantsPDF(messages: ChatMessage[]): boolean {
  const lastUser = [...messages].reverse().find((m) => m.role === "user")?.content?.toLowerCase() ?? "";
  const triggers = [
	"pdf",
	"draft a letter",
	"draft a response",
	"formal response",
	"generate a response",
	"write a letter",
	"export",
	"download",
	"send to",
	"custom letter",
  ];
  return triggers.some((t) => lastUser.includes(t));
}

function buildFallbackPdfDraft(lastUserQuestion: string): PDFDraft {
  const safe = lastUserQuestion?.trim() ? lastUserQuestion.trim() : "Request for clarification and response";
  return {
	filename: "Custom-Response.pdf",
	title: "Draft Response (Informational)",
	sections: [
	  {
		heading: "Purpose",
		body:
		  "This draft is a general informational response based on the provided document context. It is not legal advice.\n\n" +
		  "It is intended to (1) confirm understanding, (2) request clarifications, and (3) propose next steps.",
	  },
	  { heading: "What I’m responding to", body: safe },
	  {
		heading: "Questions / Clarifications",
		body:
		  "1) Please confirm the key obligations for each party and where they appear in the document.\n" +
		  "2) Please confirm all deadlines, notice requirements, and cure periods.\n" +
		  "3) Please identify any penalty, fee, interest, liquidated damages, attorneys’ fees, or termination/default consequences.\n" +
		  "4) Please confirm any limitation of liability, indemnity scope, warranties/disclaimers, and dispute resolution process.\n",
	  },
	  {
		heading: "Requested adjustments (if applicable)",
		body:
		  "If any terms are ambiguous or one-sided, please propose revised language that clarifies obligations, balances risk allocation, and removes hidden catches.",
	  },
	  {
		heading: "Closing",
		body: "Please respond in writing and reference the specific section(s) for each answer. Thank you.\n\nSincerely,",
	  },
	],
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
	const url = new URL(request.url);
	const pathname = normalizePathname(url.pathname);

	if (request.method === "OPTIONS") {
	  return new Response(null, { status: 204, headers: corsHeaders });
	}

	if (request.method === "GET" && pathname === "/") {
	  return json({ ok: true, service: "documentreader-api" });
	}

	const isAnalyzeDocument = pathname === "/analyze/document" || pathname === "/analyze/debt-letter";
	const isChatDocument = pathname === "/chat/document" || pathname === "/chat/debt-letter";

	if (!isAnalyzeDocument && !isChatDocument) {
	  return json({ error: "Not found" }, 404);
	}

	if (request.method !== "POST") {
	  return json({ error: "Use POST" }, 405);
	}

	let body: any;
	try {
	  body = await request.json();
	} catch {
	  return json({ error: "Invalid JSON" }, 400);
	}

	// ---------------------------
	// ANALYZE
	// ---------------------------
	if (isAnalyzeDocument) {
	  const req = body as DocumentAnalyzeRequest;
	  const text = typeof req?.text === "string" ? req.text : "";
	  const detail_level = normalizeDetailLevel(req?.detail_level);

	  if (text.trim().length < 20) {
		return json({ error: "Text too short" }, 400);
	  }

	  if (!env.OPENAI_API_KEY) {
		return json(fallbackResponse(detail_level, "OPENAI_API_KEY is missing."));
	  }

	  const verbosityRule =
		detail_level === "short"
		  ? "Keep it concise."
		  : detail_level === "long"
		  ? "Be very detailed."
		  : "Be moderately detailed.";

	  const system = `
You analyze legal documents and return structured information.

Return ONLY valid JSON (no markdown, no backticks).
Match this exact JSON shape:

{
  "doc_type": string,
  "confidence": number,
  "summary_plain": string,

  "simple_english": string,

  "eli5_paragraphs": [string, string],
  "eli5_analogy": string,

  "party_analysis": [
	{
	  "party": string,
	  "role_title": string,
	  "benefits": [string],
	  "liabilities": [string],
	  "possible_penalties": [string],
	  "catches": [string],
	  "rights": [
		{
		  "right": string,
		  "details": string,
		  "source": string|null,
		  "citations": [
			{
			  "source_type": "document"|"external",
			  "source": string,
			  "quote": string|null,
			  "url": string|null
			}
		  ]
		}
	  ]
	}
  ],

  "who_benefits_most": { "party": string, "confidence": number, "reasons": [string] },

  "analysis_paragraphs": [string, string, string],

  "key_facts": {
	"parties": [string],
	"dates": [{"label": string, "value": string, "source": string|null}],
	"amounts": [{"label": string, "value": number, "currency": string, "source": string|null}],
	"obligations": [string],
	"deadlines": [string],
	"governing_law": string|null,
	"key_points": [string]
  },

  "urgency": {"level":"low"|"medium"|"high", "reasons":[string]},
  "next_steps": [{"title": string, "detail": string}],
  "red_flags": [string],

  "drafts": {
	"response_draft_short": string,
	"response_draft_medium": string,
	"response_draft_long": string,
	"questions_for_advisor": string
  } | null,

  "limitations": [string],
  "suggested_questions": [string]
}

Rules:
- simple_english: ~6th–8th grade reading level.
- eli5_paragraphs: MUST be exactly 2 paragraphs. Simple, concrete.
- eli5_analogy: concrete analogy.
- party_analysis:
  - Identify parties from the document.
  - role_title MUST be derived from the document if possible (e.g., Landlord, Tenant, Buyer, Seller, Lender, Borrower).
  - If role titles are not explicitly stated, set role_title to "Party 1", "Party 2", etc.
- rights:
  - Each right should be a clear entitlement/permission/remedy granted by the document (e.g., terminate, enter premises, demand payment, withhold performance, cure, inspect, notice).
  - Each right MUST include a "source" if you can (Section/Page/Clause label), otherwise null.
  - citations should prefer source_type="document" with a short quote snippet from the OCR text.
  - Use external citations ONLY if explicitly requested AND you are confident; otherwise omit or keep external urls null.
- liabilities: include obligations + restrictions.
- possible_penalties: include remedies/consequences for breach if described.
- catches: gotchas/conditions/exceptions.
- who_benefits_most.party must be one of the listed parties or "Unclear".
- analysis_paragraphs MUST be EXACTLY 3 paragraphs.
- If unknown, use empty arrays or null where allowed.
- Always include "Not legal advice." in limitations.
- ${verbosityRule}
`.trim();

	  const user = `Document text:\n\n${text}`;

	  try {
		const content = await callOpenAIChat(env, [
		  { role: "system", content: system },
		  { role: "user", content: user },
		]);

		const parsed = safeParseJSON(content) as DocumentAnalyzeResponse;

		const analysis_paragraphs =
		  Array.isArray((parsed as any)?.analysis_paragraphs) && (parsed as any).analysis_paragraphs.length === 3
			? ((parsed as any).analysis_paragraphs as [string, string, string])
			: ([
				"This appears to be a legal document setting obligations and rules between parties.",
				"Key risks and duties depend on the specific terms, deadlines, and remedies described.",
				"Consider clarifying unclear clauses and understanding liabilities before relying on it.",
			  ] as [string, string, string]);

		const drafts =
		  (parsed as any)?.drafts && typeof (parsed as any)?.drafts === "object"
			? (parsed as any).drafts
			: buildDrafts(detail_level);

		const simple_english =
		  typeof (parsed as any)?.simple_english === "string" && (parsed as any).simple_english.trim()
			? (parsed as any).simple_english
			: fallbackResponse(detail_level, "Missing simple_english.").simple_english;

		const eli5_paragraphs =
		  Array.isArray((parsed as any)?.eli5_paragraphs) && (parsed as any).eli5_paragraphs.length === 2
			? ((parsed as any).eli5_paragraphs as [string, string])
			: fallbackResponse(detail_level, "Missing eli5_paragraphs.").eli5_paragraphs;

		const eli5_analogy =
		  typeof (parsed as any)?.eli5_analogy === "string" && (parsed as any).eli5_analogy.trim()
			? (parsed as any).eli5_analogy
			: fallbackResponse(detail_level, "Missing eli5_analogy.").eli5_analogy;

		const party_analysis =
		  Array.isArray((parsed as any)?.party_analysis) && (parsed as any).party_analysis.length > 0
			? (parsed as any).party_analysis.map((p: any, idx: number) => ({
				party: typeof p?.party === "string" && p.party.trim() ? p.party : `Party ${idx + 1}`,
				role_title:
				  typeof p?.role_title === "string" && p.role_title.trim() ? p.role_title : `Party ${idx + 1}`,
				benefits: Array.isArray(p?.benefits) ? p.benefits : [],
				liabilities: Array.isArray(p?.liabilities) ? p.liabilities : [],
				possible_penalties: Array.isArray(p?.possible_penalties) ? p.possible_penalties : [],
				catches: Array.isArray(p?.catches) ? p.catches : [],
				rights: Array.isArray(p?.rights)
				  ? p.rights.map((r: any) => ({
					  right: typeof r?.right === "string" ? r.right : "",
					  details: typeof r?.details === "string" ? r.details : "",
					  source: typeof r?.source === "string" ? r.source : null,
					  citations: Array.isArray(r?.citations)
						? r.citations.map((c: any) => ({
							source_type: c?.source_type === "external" ? "external" : "document",
							source: typeof c?.source === "string" ? c.source : "",
							quote: typeof c?.quote === "string" ? c.quote : null,
							url: typeof c?.url === "string" ? c.url : null,
						  }))
						: [],
					}))
				  : [],
			  }))
			: fallbackResponse(detail_level, "Missing party_analysis.").party_analysis;

		const who_benefits_most =
		  (parsed as any)?.who_benefits_most && typeof (parsed as any).who_benefits_most === "object"
			? (parsed as any).who_benefits_most
			: fallbackResponse(detail_level, "Missing who_benefits_most.").who_benefits_most;

		const limitations: string[] = Array.isArray((parsed as any)?.limitations) ? (parsed as any).limitations : [];
		if (!limitations.some((s) => typeof s === "string" && s.toLowerCase().includes("not legal advice"))) {
		  limitations.unshift("Not legal advice.");
		}

		return json({
		  ...(parsed as any),
		  analysis_paragraphs,
		  drafts,
		  simple_english,
		  eli5_paragraphs,
		  eli5_analogy,
		  party_analysis,
		  who_benefits_most,
		  limitations,
		} satisfies DocumentAnalyzeResponse);
	  } catch (e: any) {
		const status = e?.status ?? 500;
		const errText = typeof e?.body === "string" ? e.body : String(e?.message ?? e);

		const fb = fallbackResponse(detail_level, `OpenAI request failed (HTTP ${status}).`);
		fb.limitations = ["Not legal advice.", "OpenAI request failed.", errText.slice(0, 300)];
		fb.drafts = buildDrafts(detail_level);
		return json(fb, 200);
	  }
	}

	// ---------------------------
	// CHAT
	// ---------------------------
	if (isChatDocument) {
	  const req = body as ChatRequest;
	  const document_text = typeof req?.document_text === "string" ? req.document_text : "";
	  const messages = Array.isArray(req?.messages) ? (req.messages as ChatMessage[]) : [];
	  const detail_level = normalizeDetailLevel(req?.detail_level);

	  if (document_text.trim().length < 20) {
		return json({ error: "document_text too short" }, 400);
	  }

	  const lastUser = [...messages].reverse().find((m) => m.role === "user")?.content ?? "";

	  if (!env.OPENAI_API_KEY) {
		return json({
		  reply:
			`I can only answer questions about the uploaded document and its legal subject matter.\n\n` +
			`Your question: "${lastUser}"\n\n` +
			`I cannot run a full AI analysis right now because OPENAI_API_KEY is not configured.`,
		  limitations: ["Not legal advice.", "No OpenAI key configured."],
		} satisfies ChatResponse);
	  }

	  const verbosityRule =
		detail_level === "short"
		  ? "Keep replies concise."
		  : detail_level === "long"
		  ? "Be very detailed and thorough."
		  : "Be moderately detailed.";

	  const wantsPDF = userWantsPDF(messages);

	  const baseSystem = `
You are a document-focused legal information assistant.

STRICT SCOPE RULES:
- Only answer questions that relate to the provided document text and its legal subject matter.
- If the user asks something unrelated, refuse briefly and instruct them to ask about the document.
- Do not provide legal advice. Provide general information, explain terms, and point to relevant clauses if possible.
- If you assert something about what the document says, try to cite the document clause in your wording (e.g., "In Section X...").

${verbosityRule}
`.trim();

	  const docContext = `Document text (context):\n\n${document_text}`;

	  const history = messages
		.filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
		.map((m) => ({ role: m.role, content: m.content }));

	  try {
		if (wantsPDF) {
		  const pdfSystem = `
${baseSystem}

Return ONLY valid JSON (no markdown, no backticks), matching EXACTLY:

{
  "reply": string,
  "pdf_draft": {
	"filename": string,
	"title": string,
	"sections": [
	  { "heading": string, "body": string }
	]
  },
  "limitations": [string]
}

Rules for pdf_draft:
- Keep it informational, not legal advice.
- Reference document clauses where possible.
- limitations MUST include "Not legal advice."
`.trim();

		  const content = await callOpenAIChat(env, [
			{ role: "system", content: pdfSystem },
			{ role: "user", content: docContext },
			...history,
			{ role: "user", content: `User request: ${lastUser}` },
		  ]);

		  let parsed: any;
		  try {
			parsed = safeParseJSON(content);
		  } catch {
			const fallbackDraft = buildFallbackPdfDraft(lastUser);
			return json({
			  reply: "I drafted a structured response for a PDF export based on your request (informational only).",
			  pdf_draft: fallbackDraft,
			  limitations: ["Not legal advice.", "PDF draft generated in fallback mode."],
			} satisfies ChatResponse);
		  }

		  const reply = typeof parsed?.reply === "string" ? parsed.reply.trim() : "";
		  const pdf_draft = parsed?.pdf_draft;

		  const safeDraft: PDFDraft =
			pdf_draft && typeof pdf_draft === "object"
			  ? {
				  filename: typeof pdf_draft.filename === "string" ? pdf_draft.filename : "Custom-Response.pdf",
				  title: typeof pdf_draft.title === "string" ? pdf_draft.title : "Draft Response",
				  sections: Array.isArray(pdf_draft.sections)
					? pdf_draft.sections.map((s: any) => ({
						heading: typeof s?.heading === "string" ? s.heading : "",
						body: typeof s?.body === "string" ? s.body : "",
					  }))
					: buildFallbackPdfDraft(lastUser).sections,
				}
			  : buildFallbackPdfDraft(lastUser);

		  const limitations: string[] = Array.isArray(parsed?.limitations) ? parsed.limitations : [];
		  if (!limitations.some((s) => typeof s === "string" && s.toLowerCase().includes("not legal advice"))) {
			limitations.unshift("Not legal advice.");
		  }

		  return json({
			reply: reply || "I drafted a PDF response (informational only).",
			pdf_draft: safeDraft,
			limitations,
		  } satisfies ChatResponse);
		}

		const reply = await callOpenAIChat(env, [
		  { role: "system", content: baseSystem },
		  { role: "user", content: docContext },
		  ...history,
		]);

		return json({
		  reply: reply.trim(),
		  limitations: ["Not legal advice."],
		} satisfies ChatResponse);
	  } catch (e: any) {
		const status = e?.status ?? 500;
		const errText = typeof e?.body === "string" ? e.body : String(e?.message ?? e);

		return json({
		  reply: `Chat failed (HTTP ${status}). Try again.`,
		  limitations: ["Not legal advice.", "Chat request failed.", errText.slice(0, 200)],
		} satisfies ChatResponse);
	  }
	}

	return json({ error: "Not found" }, 404);
  },
};
