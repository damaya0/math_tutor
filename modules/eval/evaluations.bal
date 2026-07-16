import ballerina/ai;
import ballerina/time;
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

# The matching strategies supported by the tool-trajectory evaluation.
public enum Mode {
    # The agent must make exactly the reference tool calls, in the same order
    STRICT,
    # The agent must make exactly the reference tool calls, in any order
    UNORDERED,
    # The agent may only make tool calls that appear in the reference (no extras);
    # it does not have to make all of them
    SUBSET,
    # The agent must make at least all the reference tool calls; extra calls are allowed
    SUPERSET
}

# Checks the agent's tool calls against the trajectory recorded in the eval set.
# A tool call matches when both the tool name and its arguments are equal;
# tool-call IDs are ignored since they differ between runs.
#
# The strictness of the comparison is controlled by `matchMode`:
# `STRICT` (exact calls, same order), `UNORDERED` (exact calls, any order),
# `SUBSET` (no calls outside the reference), `SUPERSET` (all reference calls
# present, extras allowed).
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + matchMode - The trajectory matching strategy to apply
# + return - `()` if every trace passes, or an error describing the first mismatch
@EvalTemplate {
    label: "Tool Trajectory",
    description: "Checks the agent's tool calls against the eval set trajectory using a configurable matching mode",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function evaluateToolTrajectory(ai:Agent targetAgent, ai:ConversationThread thread,
        Mode matchMode = STRICT) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = thread.id);
        ai:FunctionCall[] expectedToolCalls = expectedTrace.toolCalls ?: [];
        ai:FunctionCall[] actualToolCalls = actualTrace.toolCalls ?: [];
        if !matchTrajectory(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls,
                matchMode = matchMode) {
            return error(string `[tool-trajectory] query "${userQuery}": tool calls do not satisfy ${matchMode} matching; expected ${describeToolCalls(toolCalls = expectedToolCalls)} but got ${describeToolCalls(toolCalls = actualToolCalls)}`);
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

# Checks that agent responses contain none of the prohibited strings.
#
# Accepts either a conversation thread loaded from an eval set (every trace is
# replayed into the thread's session; the whole thread fails if even one response
# contains a prohibited string) or a single user query (run in a fresh, randomly
# generated session).
#
# An empty prohibited list is treated as a configuration error and fails.
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + prohibitedStrings - The strings that must not appear in any agent response
# + caseSensitive - Whether the matching is case-sensitive
# + return - `()` if no prohibited content is found, or an error describing the first violation
@EvalTemplate {
    label: "Content Safety",
    description: "Checks that agent responses contain none of the configured prohibited strings",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertContentSafety(ai:Agent targetAgent, ai:ConversationThread|string queries,
        string[] prohibitedStrings, boolean caseSensitive = false) returns error? {
    if prohibitedStrings.length() == 0 {
        return error("[content-safety] no prohibited strings configured; add at least one prohibited string");
    }
    if queries is string {
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkProhibitedContent(userQuery = queries, actualResponse = actualResponse,
                prohibitedStrings = prohibitedStrings, caseSensitive = caseSensitive);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = queries.id);
        check checkProhibitedContent(userQuery = userQuery, actualResponse = actualResponse,
                prohibitedStrings = prohibitedStrings, caseSensitive = caseSensitive);
    }
}

# Checks that the expected response recorded in the eval set appears as a substring
# of the agent response. Useful when the agent may elaborate but must include a
# canonical answer verbatim.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + caseSensitive - Whether the substring matching is case-sensitive
# + return - `()` if every trace passes, or an error describing the first miss
@EvalTemplate {
    label: "Contains Match",
    description: "Checks that the expected response from the eval set appears as a substring of the agent response",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function assertContainsMatch(ai:Agent targetAgent, ai:ConversationThread thread,
        boolean caseSensitive = false) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check expectedTrace.output;
        string expectedResponse = expectedOutput.content ?: "";
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = thread.id);
        string compareExpected = caseSensitive ? expectedResponse : expectedResponse.toLowerAscii();
        string compareActual = caseSensitive ? actualResponse : actualResponse.toLowerAscii();
        if !compareActual.includes(compareExpected) {
            return error(string `[contains-match] query "${userQuery}": expected response not found in agent response (actual length ${actualResponse.length()}, expected length ${expectedResponse.length()})`);
        }
    }
}

# Checks that the agent completes every run within the given number of iterations.
#
# Accepts either a conversation thread loaded from an eval set (every trace is
# replayed into the thread's session and its run checked) or a single user query
# (run in a fresh, randomly generated session).
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + maxIterations - The maximum number of iterations allowed per agent run
# + return - `()` if every run stays within the limit, or an error describing the first excess
@EvalTemplate {
    label: "Iteration Efficiency",
    description: "Checks that the agent completes each run within the configured iteration limit",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertIterationEfficiency(ai:Agent targetAgent, ai:ConversationThread|string queries,
        int maxIterations = 5) returns error? {
    if queries is string {
        ai:Trace actualTrace = check targetAgent.run(query = queries, sessionId = uuid:createType4AsString());
        return checkIterationCount(userQuery = queries, actualTrace = actualTrace,
                maxIterations = maxIterations);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = queries.id);
        check checkIterationCount(userQuery = userQuery, actualTrace = actualTrace,
                maxIterations = maxIterations);
    }
}

# Checks that the agent produces every response within the given time limit.
#
# Accepts either a conversation thread loaded from an eval set (every trace is
# replayed into the thread's session and its run timed) or a single user query
# (run in a fresh, randomly generated session).
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + maxLatencySeconds - The maximum time allowed per agent run, in seconds
# + return - `()` if every run finishes within the limit, or an error describing the first excess
@EvalTemplate {
    label: "Latency Performance",
    description: "Checks that the agent responds within the configured time limit",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertLatencyPerformance(ai:Agent targetAgent, ai:ConversationThread|string queries,
        decimal maxLatencySeconds = 10) returns error? {
    if queries is string {
        ai:Trace actualTrace = check targetAgent.run(query = queries, sessionId = uuid:createType4AsString());
        return checkLatency(userQuery = queries, actualTrace = actualTrace,
                maxLatencySeconds = maxLatencySeconds);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = queries.id);
        check checkLatency(userQuery = userQuery, actualTrace = actualTrace,
                maxLatencySeconds = maxLatencySeconds);
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

isolated function checkProhibitedContent(string userQuery, string actualResponse, string[] prohibitedStrings,
        boolean caseSensitive) returns error? {
    string compareResponse = caseSensitive ? actualResponse : actualResponse.toLowerAscii();
    string[] foundStrings = [];
    foreach string prohibitedString in prohibitedStrings {
        string compareProhibited = caseSensitive ? prohibitedString : prohibitedString.toLowerAscii();
        if compareResponse.includes(compareProhibited) {
            foundStrings.push(prohibitedString);
        }
    }
    if foundStrings.length() > 0 {
        return error(string `[content-safety] query "${userQuery}": response contains ${foundStrings.length()} prohibited string(s): "${string:'join("\", \"", ...foundStrings)}"`);
    }
}

isolated function checkLatency(string userQuery, ai:Trace actualTrace, decimal maxLatencySeconds)
        returns error? {
    decimal actualLatencySeconds = time:utcDiffSeconds(actualTrace.endTime, actualTrace.startTime);
    if actualLatencySeconds > maxLatencySeconds {
        return error(string `[latency-performance] query "${userQuery}": agent responded in ${actualLatencySeconds}s, exceeding the limit of ${maxLatencySeconds}s`);
    }
}

isolated function checkIterationCount(string userQuery, ai:Trace actualTrace, int maxIterations)
        returns error? {
    int actualIterations = actualTrace.iterations.length();
    if actualIterations > maxIterations {
        return error(string `[iteration-efficiency] query "${userQuery}": agent used ${actualIterations} iterations, exceeding the limit of ${maxIterations}`);
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

isolated function matchTrajectory(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls,
        Mode matchMode) returns boolean {
    match matchMode {
        STRICT => {
            return matchStrict(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        UNORDERED => {
            return matchUnordered(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        SUBSET => {
            return matchSubset(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        SUPERSET => {
            return matchSuperset(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
    }
    return false;
}

isolated function callsMatch(ai:FunctionCall expectedCall, ai:FunctionCall actualCall) returns boolean =>
    expectedCall.name == actualCall.name && expectedCall.arguments == actualCall.arguments;

isolated function matchStrict(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    foreach int callIndex in 0 ..< expectedToolCalls.length() {
        if !callsMatch(expectedCall = expectedToolCalls[callIndex], actualCall = actualToolCalls[callIndex]) {
            return false;
        }
    }
    return true;
}

isolated function matchUnordered(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    boolean[] matchedFlags = actualToolCalls.'map(actualCall => false);
    foreach ai:FunctionCall expectedCall in expectedToolCalls {
        boolean foundMatch = false;
        foreach int actualIndex in 0 ..< actualToolCalls.length() {
            if !matchedFlags[actualIndex]
                    && callsMatch(expectedCall = expectedCall, actualCall = actualToolCalls[actualIndex]) {
                matchedFlags[actualIndex] = true;
                foundMatch = true;
                break;
            }
        }
        if !foundMatch {
            return false;
        }
    }
    return true;
}

isolated function matchSubset(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    foreach ai:FunctionCall actualCall in actualToolCalls {
        if !containsCall(toolCalls = expectedToolCalls, targetCall = actualCall) {
            return false;
        }
    }
    return true;
}

isolated function matchSuperset(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    foreach ai:FunctionCall expectedCall in expectedToolCalls {
        if !containsCall(toolCalls = actualToolCalls, targetCall = expectedCall) {
            return false;
        }
    }
    return true;
}

isolated function containsCall(ai:FunctionCall[] toolCalls, ai:FunctionCall targetCall) returns boolean {
    foreach ai:FunctionCall toolCall in toolCalls {
        if callsMatch(expectedCall = targetCall, actualCall = toolCall) {
            return true;
        }
    }
    return false;
}

isolated function describeToolCalls(ai:FunctionCall[] toolCalls) returns string {
    string[] callDescriptions = toolCalls.'map(toolCall =>
        string `${toolCall.name}(${(toolCall.arguments ?: {}).toJsonString()})`);
    return "[" + string:'join(", ", ...callDescriptions) + "]";
}
