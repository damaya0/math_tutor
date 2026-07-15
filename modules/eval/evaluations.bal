import ballerina/ai;
import ballerina/uuid;

# The structured output of an LLM judge: a score plus the reasoning behind it.
# The reasoning is surfaced only in failure errors; passing evaluations stay silent.
type JudgeVerdict record {|
    # The score assigned by the judge, in the range [0.0, 1.0]
    float evalScore;
    # A brief justification for the assigned score
    string judgeReasoning;
|};

// ***** Rule-based evaluations *****

# Checks that agent response lengths fall within the given bounds (inclusive).
#
# Accepts either a conversation thread loaded from an eval set (every trace is
# replayed into the thread's session and checked) or a single user query (run in
# a fresh, randomly generated session with no leftover memory).
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + minLength - The minimum accepted response length (inclusive)
# + maxLength - The maximum accepted response length (inclusive)
# + return - `()` if every checked response passes, or an error describing the first failure
@EvalTemplate {
    label: "Length Compliance",
    description: "Checks that agent response lengths stay within the configured bounds",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertLengthCompliance(ai:Agent targetAgent, ai:ConversationThread|string queries,
        int minLength = 1, int maxLength = 10000) returns error? {
    if queries is string {
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkLength(userQuery = queries, actualResponse = actualResponse,
                minLength = minLength, maxLength = maxLength);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = queries.id);
        check checkLength(userQuery = userQuery, actualResponse = actualResponse,
                minLength = minLength, maxLength = maxLength);
    }
}

# Checks that the agent invokes the same tools, in the same order and with the same
# arguments, as recorded in the eval set. Tool-call IDs are ignored since they differ
# between runs.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + return - `()` if every trace passes, or an error describing the first mismatch
@EvalTemplate {
    label: "Tool Trajectory",
    description: "Checks that the agent invokes the same tools with the same arguments as the eval set",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function evaluateToolTrajectory(ai:Agent targetAgent, ai:ConversationThread thread)
        returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = thread.id);
        ai:FunctionCall[] expectedToolCalls = expectedTrace.toolCalls ?: [];
        ai:FunctionCall[] actualToolCalls = actualTrace.toolCalls ?: [];
        if !matchToolCalls(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls) {
            return error(string `[tool-trajectory] query "${userQuery}": expected tool calls ${describeToolCalls(toolCalls = expectedToolCalls)} but got ${describeToolCalls(toolCalls = actualToolCalls)}`);
        }
    }
}

# Checks that every agent response exactly matches the expected response recorded
# in the eval set. By default, leading/trailing whitespace is stripped before
# comparing; every other character — including inner whitespace, punctuation, and
# formatting — must match exactly.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + caseSensitive - Whether the comparison is case-sensitive
# + stripWhitespace - Whether to strip leading/trailing whitespace before comparing
# + return - `()` if every trace matches, or an error describing the first mismatch
@EvalTemplate {
    label: "Exact Match",
    description: "Checks that each agent response exactly matches the expected response in the eval set",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function assertExactMatch(ai:Agent targetAgent, ai:ConversationThread thread,
        boolean caseSensitive = true, boolean stripWhitespace = true) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check expectedTrace.output;
        string rawExpected = expectedOutput.content ?: "";
        string rawActual = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = thread.id);
        string expectedResponse = stripWhitespace ? rawExpected.trim() : rawExpected;
        string actualResponse = stripWhitespace ? rawActual.trim() : rawActual;
        if !caseSensitive {
            expectedResponse = expectedResponse.toLowerAscii();
            actualResponse = actualResponse.toLowerAscii();
        }
        if actualResponse != expectedResponse {
            int mismatchIndex = findFirstMismatch(expectedResponse = expectedResponse,
                    actualResponse = actualResponse);
            return error(string `[exact-match] query "${userQuery}": responses differ at character index ${mismatchIndex} (expected lengths ${expectedResponse.length()}, actual ${actualResponse.length()}); expected "…${excerptAround(text = expectedResponse, mismatchIndex = mismatchIndex)}…" but got "…${excerptAround(text = actualResponse, mismatchIndex = mismatchIndex)}…"`);
        }
    }
}

// ***** LLM-as-judge evaluations *****

# Uses an LLM judge to check that every agent response for the thread conveys the
# same meaning as the reference response recorded in the eval set.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + judgeModel - The model provider used as the LLM judge
# + judgeScoreThreshold - The minimum judge score (in [0.0, 1.0]) required to pass
# + return - `()` if every trace passes, or an error describing the first failure
@EvalTemplate {
    label: "Semantic Similarity",
    description: "Uses an LLM judge to compare each agent response against the expected response in the eval set",
    kind: LLM_JUDGE,
    needsEvalset: true
}
public isolated function evaluateSemanticSimilarity(ai:Agent targetAgent, ai:ConversationThread thread,
        ai:ModelProvider judgeModel, float judgeScoreThreshold = 0.8) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check expectedTrace.output;
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = thread.id);
        ai:ChatAssistantMessage actualOutput = check actualTrace.output;
        JudgeVerdict judgeVerdict = check judgeModel->generate(`You are an expert evaluator. Your sole criterion is SEMANTIC SIMILARITY: does the actual response convey the same meaning as the expected response?

        User Query: ${userQuery}
        Actual Response: ${actualOutput.content.toString()}
        Expected Response: ${expectedOutput.content.toString()}
        Evaluation Steps:
        1. Identify the key facts, conclusions, and meaning in the expected response.
        2. Identify the same elements in the actual response.
        3. Compare for semantic equivalence: focus on MEANING, not exact wording. Paraphrases and synonymous expressions count as matches.
        4. Identify any meaningful factual differences that change the answer.

        Do NOT penalize differences in wording, formatting, or phrasing. Only deduct for genuinely different content or meaning.

        Scoring Rubric:
        0.0  = Completely different meaning; the actual response answers a different question or provides contradictory information
        0.25 = Some surface similarity but the core answer or key facts differ
        0.5  = Partially overlapping meaning; some key facts match but others differ
        0.75 = Mostly equivalent; only minor factual nuances differ
        1.0  = Semantically equivalent: same meaning, same key facts, even if worded differently

        Along with the score, provide a brief reasoning that justifies it, citing the specific similarities or differences you found.`);
        check checkScore(metricName = "semantic-similarity", userQuery = userQuery,
                judgeVerdict = judgeVerdict, passingScore = judgeScoreThreshold);
    }
}

# Uses an LLM judge to check that the factual information in agent responses is
# correct and reliable.
#
# Accepts either a conversation thread loaded from an eval set (every trace is
# replayed into the thread's session and judged) or a single user query (run in
# a fresh, randomly generated session with no leftover memory).
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + judgeModel - The model provider used as the LLM judge
# + judgeScoreThreshold - The minimum judge score (in [0.0, 1.0]) required to pass
# + return - `()` if every judged response passes, or an error describing the first failure
@EvalTemplate {
    label: "Output Accuracy",
    description: "Uses an LLM judge to check the factual correctness of agent responses",
    kind: LLM_JUDGE,
    needsEvalset: false
}
public isolated function evaluateOutputAccuracy(ai:Agent targetAgent, ai:ConversationThread|string queries,
        ai:ModelProvider judgeModel, float judgeScoreThreshold = 0.8) returns error? {
    if queries is string {
        return checkQueryAccuracy(targetAgent = targetAgent, userQuery = queries, judgeModel = judgeModel,
                judgeScoreThreshold = judgeScoreThreshold, sessionId = uuid:createType4AsString());
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        check checkQueryAccuracy(targetAgent = targetAgent, userQuery = userQuery, judgeModel = judgeModel,
                judgeScoreThreshold = judgeScoreThreshold, sessionId = queries.id);
    }
}

isolated function checkQueryAccuracy(ai:Agent targetAgent, string userQuery, ai:ModelProvider judgeModel,
        float judgeScoreThreshold, string sessionId) returns error? {
    ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = sessionId);
    ai:ChatAssistantMessage actualOutput = check actualTrace.output;
    JudgeVerdict judgeVerdict = check judgeModel->generate(`You are an expert evaluator. Your sole criterion is ACCURACY: is the factual information in the response correct and reliable?

        User Query: ${userQuery}
        Agent Response: ${actualOutput.content.toString()}

        Evaluation Steps:
        1. Identify the factual claims, technical statements, and information presented in the response.
        2. Assess whether these facts are correct based on your knowledge. Flag any statements that are demonstrably wrong, misleading, or technically imprecise.
        3. Check for subtle inaccuracies: correct general direction but wrong specifics, outdated information presented as current, or oversimplifications that mislead.
        4. Assess the overall reliability of the information provided.

        Do NOT penalize the response for information you cannot verify. Only flag claims you are confident are incorrect or misleading.

        Scoring Rubric:
        0.0  = Contains significant factual errors that would mislead the user
        0.25 = Several inaccuracies or one major factual error that undermines trust
        0.5  = Mostly accurate but with noticeable errors or misleading simplifications
        0.75 = Accurate with only minor imprecisions that do not materially mislead
        1.0  = Fully accurate; all factual claims are correct and reliably stated

        Along with the score, provide a brief reasoning that justifies it, citing the specific claims you checked.`);
    check checkScore(metricName = "accuracy", userQuery = userQuery,
            judgeVerdict = judgeVerdict, passingScore = judgeScoreThreshold);
}

// ***** Shared helpers *****

isolated function getAgentResponse(ai:Agent targetAgent, string userQuery, string sessionId)
        returns string|error {
    ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = sessionId);
    return getResponseText(trace = actualTrace);
}

isolated function getResponseText(ai:Trace trace) returns string|error {
    ai:ChatAssistantMessage output = check trace.output;
    return output.content ?: "";
}

isolated function checkLength(string userQuery, string actualResponse, int minLength, int maxLength)
        returns error? {
    int responseLength = actualResponse.length();
    if responseLength < minLength || responseLength > maxLength {
        return error(string `[length-compliance] query "${userQuery}": response length ${responseLength} is outside the range [${minLength}, ${maxLength}]`);
    }
}

isolated function checkScore(string metricName, string userQuery, JudgeVerdict judgeVerdict,
        float passingScore) returns error? {
    if judgeVerdict.evalScore < passingScore {
        return error(string `[${metricName}] query "${userQuery}": judge score ${judgeVerdict.evalScore} is below the passing score ${passingScore}. Judge reasoning: ${judgeVerdict.judgeReasoning}`);
    }
}

isolated function findFirstMismatch(string expectedResponse, string actualResponse) returns int {
    int comparableLength = int:min(expectedResponse.length(), actualResponse.length());
    foreach int charIndex in 0 ..< comparableLength {
        if expectedResponse[charIndex] != actualResponse[charIndex] {
            return charIndex;
        }
    }
    return comparableLength;
}

isolated function excerptAround(string text, int mismatchIndex) returns string {
    int windowStart = int:max(0, mismatchIndex - 20);
    int windowEnd = int:min(text.length(), mismatchIndex + 20);
    return text.substring(windowStart, windowEnd);
}

isolated function matchToolCalls(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    foreach int callIndex in 0 ..< expectedToolCalls.length() {
        ai:FunctionCall expectedCall = expectedToolCalls[callIndex];
        ai:FunctionCall actualCall = actualToolCalls[callIndex];
        if expectedCall.name != actualCall.name || expectedCall.arguments != actualCall.arguments {
            return false;
        }
    }
    return true;
}

isolated function describeToolCalls(ai:FunctionCall[] toolCalls) returns string {
    string[] callDescriptions = toolCalls.'map(toolCall =>
        string `${toolCall.name}(${(toolCall.arguments ?: {}).toJsonString()})`);
    return "[" + string:'join(", ", ...callDescriptions) + "]";
}
