// src/index.ts
//
// Cloudflare Worker for DocumentReader / Debt Letter API
// - /analyze/document (and /analyze/debt-letter): structured JSON analysis
// - /chat/document (and /chat/debt-letter): document Q&A + optional PDF draft JSON
//
// Key guarantees:
// 1) Never returns pdf_draft for abusive/off-topic user requests.
// 2) PDF generation is only allowed when:
//    - user explicitly asks for PDF AND
//    - request looks document-related AND
//    - request is not abusive/off-topic
// 3) Adds build_id to every response so you can verify deployment.
//
// NOTE: Self-contained; no external dependencies.

/* -----------------------
 * Types
 * ---------------------- */

type Amount = { label: string; value: number; currency: string; source?: string | null };
type LabeledValue = { label: string; value: string; source: string | null };
type DetailLevel = "short" | "medium" | "long";

type LegalCitation = {
  source_type: "document" | "external";
  source: string;
  quote?: string | null;
  url?: string | null;
};

type PartyRight = {
  right: string;
  details: string;
  source: string | null;
  citations: LegalCitation[];
};

type PartyBenefitsLiabilitiesPenalties = {
  party: string;
  role_title: string;
  benefits: string[];
  liabilities: string[];
  possible_penalties: string[];
  catches: string[];
  rights: PartyRight[];
};

type WhoBenefitsMost = {
  party: string;
  confidence: number;
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
  pdf_draft?: PDFDraft | null;
  pdf_allowed?: boolean; // ✅ client should only create PDF if true
  limitations?: string[];
  build_id?: string;
  openai_error?: string;
};

export interface Env {
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
}

/* -----------------------
 * Build stamp (deployment verification)
 * ---------------------- */

const BUILD_ID = "2026-02-14-guardrails-v5";

/* -----------------------
 * CORS / helpers
 * ---------------------- */

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
  const cleaned = (text || "")
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

/* -----------------------
 * Drafts / fallbacks
 * ---------------------- */

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
- Are there penalties, interest, liquidated damages, attorneys’ fees provisions?
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
	  "Imagine this paper is a set of rules for playing together. It tells each person what they must do and what they are allowed to do. If one person doesn’t follow the rules, the paper can say what happens next.",
	  "Before you say yes, you want to check: (1) what you must do, (2) when you must do it, and (3) what the consequence is if you don’t. If something is confusing, it’s okay to ask questions before agreeing.",
	],
	eli5_analogy:
	  "It’s like joining a team and signing a team rules sheet: you get to play (benefits), but you must follow rules (obligations), and there might be consequences (penalties) if you break them.",

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

	who_benefits_most: { party: "Unclear", confidence: 0.2, reasons: ["A full model analysis is not available in fallback mode."] },

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

/* -----------------------
 * Safety / guardrails
 * ---------------------- */

function isAbusiveOrOffTopicRequest(text: string): boolean {
  const t = (text || "").toLowerCase();

  // Expand as needed. This is intentionally blunt.
  const bannedPhrases = [
	"kiss my ass",
	"fuck you",
	"bitch",
	"slut",
	"whore",
	"cunt",
	"nigger",
	"fag",
	"retard",
	"kill yourself",
	"die",
  ];

  return bannedPhrases.some((p) => t.includes(p));
}

function looksLikeDocumentQuestion(text: string): boolean {
  const t = (text || "").toLowerCase();
  const docWords = [
	"start date",
	"effective date",
	"term",
	"payment",
	"bonus",
	"salary",
	"offer",
	"notice",
	"termination",
	"severance",
	"governing law",
	"arbitration",
	"confidential",
	"noncompete",
	"non-compete",
	"section",
	"clause",
	"exhibit",
	"schedule",
	"deadline",
	"fees",
	"interest",
	"penalty",
	"breach",
	"cure period",
  ];
  return docWords.some((w) => t.includes(w));
}

function userWantsPDF(messages: ChatMessage[]): boolean {
  const lastUserRaw = [...messages].reverse().find((m) => m.role === "user")?.content ?? "";
  const lastUser = lastUserRaw.toLowerCase();

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

  const wants = triggers.some((t) => lastUser.includes(t));
  if (!wants) return false;

  // Hard gates
  if (isAbusiveOrOffTopicRequest(lastUserRaw)) return false;
  if (!looksLikeDocumentQuestion(lastUserRaw)) return false;

  return true;
}

function sanitizeForPdf(text: string): string {
  const t = (text || "").trim();
  if (!t) return "Request for clarification regarding the uploaded document.";
  if (isAbusiveOrOffTopicRequest(t)) return "Request for clarification regarding the uploaded document.";
  return t.slice(0, 500);
}

function buildFallbackPdfDraft(lastUserQuestion: string): PDFDraft {
  const safe = sanitizeForPdf(lastUserQuestion);
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

/* -----------------------
 * OpenAI (Responses API)
 * ---------------------- */

type ResponsesMessage = {
  role: "system" | "user" | "assistant";
  content: Array<{ type: "input_text"; text: string }>;
};

async function callOpenAIResponses(
  env: Env,
  messages: { role: "system" | "user" | "assistant"; content: string }[],
  opts?: { json?: boolean }
): Promise<string> {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("missing_api_key");

  const model = env.OPENAI_MODEL || "gpt-5-mini";

	type ResponsesContentItem =
	  | { type: "input_text"; text: string }
	  | { type: "output_text"; text: string };

	type ResponsesMessage = {
	  role: "system" | "user" | "assistant";
	  content: ResponsesContentItem[];
	};

	// ✅ IMPORTANT: assistant messages must be output_text, not input_text
	const input: ResponsesMessage[] = messages.map((m) => ({
	  role: m.role as "system" | "user" | "assistant",
	  content: [
		{
		  type: m.role === "assistant" ? "output_text" : "input_text",
		  text: m.content,
		},
	  ],
	}));


  const body: any = {
	model,
	input,
	truncation: "auto",
  };

  if (opts?.json) {
	body.text = { format: { type: "json_object" } };
  }

  const resp = await fetch("https://api.openai.com/v1/responses", {
	method: "POST",
	headers: {
	  Authorization: `Bearer ${apiKey}`,
	  "Content-Type": "application/json",
	},
	body: JSON.stringify(body),
  });

  if (!resp.ok) {
	const errText = await resp.text().catch(() => "");
	console.log("OPENAI_ERROR_STATUS", resp.status);
	console.log("OPENAI_ERROR_BODY", errText);
	const error = new Error(`openai_http_${resp.status}`);
	(error as any).status = resp.status;
	(error as any).body = errText;
	throw error;
  }

  const data = await resp.json();

  const outputText = (data as any)?.output_text;
  if (typeof outputText === "string" && outputText.trim()) return outputText;

  const stitched =
	(data as any)?.output
	  ?.flatMap((o: any) => o?.content ?? [])
	  ?.map((c: any) => c?.text)
	  ?.filter(Boolean)
	  ?.join("\n") ?? "";

  if (typeof stitched !== "string" || !stitched.trim()) throw new Error("empty_openai_content");
  return stitched;
}

/* -----------------------
 * Worker
 * ---------------------- */

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
	const url = new URL(request.url);
	const pathname = normalizePathname(url.pathname);

	if (request.method === "OPTIONS") {
	  return new Response(null, { status: 204, headers: corsHeaders });
	}

	if (request.method === "GET" && pathname === "/") {
	  return json({ ok: true, service: "documentreader-api", build_id: BUILD_ID });
	}

	const isAnalyzeDocument = pathname === "/analyze/document" || pathname === "/analyze/debt-letter";
	const isChatDocument = pathname === "/chat/document" || pathname === "/chat/debt-letter";

	if (!isAnalyzeDocument && !isChatDocument) {
	  return json({ error: "Not found", build_id: BUILD_ID }, 404);
	}

	if (request.method !== "POST") {
	  return json({ error: "Use POST", build_id: BUILD_ID }, 405);
	}

	let body: any;
	try {
	  body = await request.json();
	} catch {
	  return json({ error: "Invalid JSON", content_type: request.headers.get("content-type") || "", build_id: BUILD_ID }, 400);
	}

	/* ---------------------------
	 * ANALYZE
	 * -------------------------- */
	if (isAnalyzeDocument) {
	  const req = body as DocumentAnalyzeRequest;
	  const text = typeof req?.text === "string" ? req.text : "";
	  const detail_level = normalizeDetailLevel(req?.detail_level);

	  if (text.trim().length < 20) {
		return json({ ...fallbackResponse(detail_level, "OCR text was empty or too short."), build_id: BUILD_ID }, 200);
	  }

	  if (!env.OPENAI_API_KEY) {
		return json({ ...fallbackResponse(detail_level, "OPENAI_API_KEY is missing."), build_id: BUILD_ID }, 200);
	  }

	  const verbosityRule =
		detail_level === "short" ? "Keep it concise." : detail_level === "long" ? "Be very detailed." : "Be moderately detailed.";

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
			{ "source_type": "document"|"external", "source": string, "quote": string|null, "url": string|null }
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
- eli5_paragraphs: EXACTLY 2.
- analysis_paragraphs: EXACTLY 3.
- Always include "Not legal advice." in limitations.
- ${verbosityRule}
`.trim();

	  const user = `Document text:\n\n${text}`;

	  try {
		const content = await callOpenAIResponses(
		  env,
		  [
			{ role: "system", content: system },
			{ role: "user", content: user },
		  ],
		  { json: true }
		);

		const parsed = safeParseJSON(content) as DocumentAnalyzeResponse;

		const limitations: string[] = Array.isArray((parsed as any)?.limitations) ? (parsed as any).limitations : [];
		if (!limitations.some((s) => typeof s === "string" && s.toLowerCase().includes("not legal advice"))) {
		  limitations.unshift("Not legal advice.");
		}

		return json(
		  {
			...(parsed as any),
			limitations,
			build_id: BUILD_ID,
		  },
		  200
		);
	  } catch (e: any) {
		const status = e?.status ?? 500;
		const errText = typeof e?.body === "string" ? e.body : String(e?.message ?? e);

		const fb = fallbackResponse(detail_level, `OpenAI request failed (HTTP ${status}).`);
		(fb as any).limitations = ["Not legal advice.", "OpenAI request failed.", errText.slice(0, 300)];
		(fb as any).drafts = buildDrafts(detail_level);

		return json({ ...fb, openai_error: errText.slice(0, 2000), build_id: BUILD_ID }, 200);
	  }
	}

	/* ---------------------------
	 * CHAT
	 * -------------------------- */
	if (isChatDocument) {
	  const req = body as ChatRequest;
	  const document_text = typeof req?.document_text === "string" ? req.document_text : "";
	  const messages = Array.isArray(req?.messages) ? (req.messages as ChatMessage[]) : [];
	  const detail_level = normalizeDetailLevel(req?.detail_level);

	  if (document_text.trim().length < 20) {
		return json(
		  {
			reply: "I couldn’t read enough text from the scan to answer. Try rescanning with better lighting or upload a clearer copy.",
			limitations: ["Not legal advice.", "OCR text was empty or too short."],
			pdf_draft: null,
			pdf_allowed: false,
			build_id: BUILD_ID,
		  } satisfies ChatResponse,
		  200
		);
	  }

	  const lastUser = [...messages].reverse().find((m) => m.role === "user")?.content ?? "";

	  // ✅ Absolute hard stop before anything else.
	  if (isAbusiveOrOffTopicRequest(lastUser)) {
		return json(
		  {
			reply: "I can’t help with abusive or inappropriate requests. Ask a question about the document instead.",
			limitations: ["Not legal advice."],
			pdf_draft: null,
			pdf_allowed: false,
			build_id: BUILD_ID,
		  } satisfies ChatResponse,
		  200
		);
	  }

	  if (!env.OPENAI_API_KEY) {
		return json(
		  {
			reply:
			  `I can only answer questions about the uploaded document and its legal subject matter.\n\n` +
			  `Your question: "${lastUser}"\n\n` +
			  `I cannot run a full AI analysis right now because OPENAI_API_KEY is not configured.`,
			limitations: ["Not legal advice.", "No OpenAI key configured."],
			pdf_draft: null,
			pdf_allowed: false,
			build_id: BUILD_ID,
		  } satisfies ChatResponse,
		  200
		);
	  }

	  const verbosityRule =
		detail_level === "short" ? "Keep replies concise." : detail_level === "long" ? "Be very detailed and thorough." : "Be moderately detailed.";

	  const wantsPDF = userWantsPDF(messages);

	  const baseSystem = `
You are a document-focused legal information assistant.

STRICT SCOPE RULES:
- Only answer questions that relate to the provided document text and its legal subject matter.
- If the user asks something unrelated, refuse briefly and instruct them to ask about the document.
- Do not provide legal advice. Provide general information and explain terms.

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
  } | null,
  "limitations": [string]
}

Rules:
- Keep it informational, not legal advice.
- If the user request is not document-related, set pdf_draft to null and refuse briefly.
- limitations MUST include "Not legal advice."
`.trim();

		  const content = await callOpenAIResponses(
			env,
			[
			  { role: "system", content: pdfSystem },
			  { role: "user", content: docContext },
			  ...history,
			  { role: "user", content: `User request: ${lastUser}` },
			],
			{ json: true }
		  );

		  let parsed: any;
		  try {
			parsed = safeParseJSON(content);
		  } catch {
			// Never fallback-generate a pdf for anything that doesn't look doc-related
			if (!looksLikeDocumentQuestion(lastUser) || isAbusiveOrOffTopicRequest(lastUser)) {
			  return json(
				{
				  reply: "I can’t generate a PDF for that. Ask a document-related question instead.",
				  limitations: ["Not legal advice."],
				  pdf_draft: null,
				  pdf_allowed: false,
				  build_id: BUILD_ID,
				} satisfies ChatResponse,
				200
			  );
			}

			// Safe fallback (doc-related only)
			const fallbackDraft = buildFallbackPdfDraft(lastUser);
			return json(
			  {
				reply: "I drafted a structured response for a PDF export based on your request (informational only).",
				pdf_draft: fallbackDraft,
				pdf_allowed: true,
				limitations: ["Not legal advice.", "PDF draft generated in fallback mode."],
				build_id: BUILD_ID,
			  } satisfies ChatResponse,
			  200
			);
		  }

		  // ✅ SERVER-SIDE OVERRIDE: even if model returns pdf_draft, block it if request becomes abusive/off-topic
		  if (isAbusiveOrOffTopicRequest(lastUser) || !looksLikeDocumentQuestion(lastUser)) {
			return json(
			  {
				reply:
				  "I can’t generate a PDF for that request. Ask a document-related question instead (e.g., start date, bonus, termination, deadlines).",
				limitations: ["Not legal advice."],
				pdf_draft: null,
				pdf_allowed: false,
				build_id: BUILD_ID,
			  } satisfies ChatResponse,
			  200
			);
		  }

		  const reply = typeof parsed?.reply === "string" ? parsed.reply.trim() : "";
		  const pdf_draft = parsed?.pdf_draft;

		  if (pdf_draft === null) {
			const limitations: string[] = Array.isArray(parsed?.limitations) ? parsed.limitations : ["Not legal advice."];
			if (!limitations.some((s) => typeof s === "string" && s.toLowerCase().includes("not legal advice"))) limitations.unshift("Not legal advice.");
			return json(
			  {
				reply: reply || "I can’t generate a PDF for that. Ask a document-related question instead.",
				pdf_draft: null,
				pdf_allowed: false,
				limitations,
				build_id: BUILD_ID,
			  } satisfies ChatResponse,
			  200
			);
		  }

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

		  return json(
			{
			  reply: reply || "I drafted a PDF response (informational only).",
			  pdf_draft: safeDraft,
			  pdf_allowed: true,
			  limitations,
			  build_id: BUILD_ID,
			} satisfies ChatResponse,
			200
		  );
		}

		// Normal chat (no PDF)
		const reply = await callOpenAIResponses(env, [
		  { role: "system", content: baseSystem },
		  { role: "user", content: docContext },
		  ...history,
		]);

		return json(
		  {
			reply: reply.trim(),
			limitations: ["Not legal advice."],
			pdf_draft: null,
			pdf_allowed: false,
			build_id: BUILD_ID,
		  } satisfies ChatResponse,
		  200
		);
	  } catch (e: any) {
		const status = e?.status ?? 500;
		const errText = typeof e?.body === "string" ? e.body : String(e?.message ?? e);

		return json(
		  {
			reply: `Chat failed (HTTP ${status}). Try again.`,
			limitations: ["Not legal advice.", "Chat request failed.", errText.slice(0, 200)],
			openai_error: errText.slice(0, 2000),
			pdf_draft: null,
			pdf_allowed: false,
			build_id: BUILD_ID,
		  } as any,
		  200
		);
	  }
	}

	return json({ error: "Not found", build_id: BUILD_ID }, 404);
  },
};
