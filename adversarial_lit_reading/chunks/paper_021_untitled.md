# Page 1

A comparative evaluation of chain-of-thought-based prompt engineering 
techniques for medical question answering
Sohyeon Jeon a
, Hong-Gee Kim b,*
a Interdisciplinary Program of Medical Informatics, College of Medicine, Seoul National University, Republic of Korea
b School of Dentistry and Dental Research Institute, Seoul National University, Republic of Korea
A R T I C L E I N F O
Keywords:
Large language models
Prompt engineering
Chain-of-thought
Question answering
Medical AI
A B S T R A C T
Background and objective: Large language models (LLMs) hold transformative potential for clinical decision- 
making in the rapidly advancing field of AI in medicine. This study evaluates how Chain-of-Thought (CoT) 
prompting techniques affect medical reasoning performance with consideration for clinical applicability.
Methods: Five LLMs (GPT-4o-mini, GPT-3.5-turbo, o1-mini, Gemini-1.5-Flash, Gemini-1.0-pro) were assessed via 
API access using CoT prompting methods exhibiting distinct cognitive characteristics. Evaluations included 
clinical datasets and non-clinical datasets. An iterative QA system was constructed to ensure consistent and 
reproducible results.
Results: o1-mini achieved the highest performance with 88.4 % accuracy in EHRNoteQA using MIMIC-IV 
discharge summaries. Traditional CoT consistently provided stable results across clinical datasets, while Inter­
active CoT showed variability - underperforming in complex medical reasoning tasks like MedMCQA (61.7 %) 
but performing well in clinical notes (83.5 % in EHRNoteQA). Statistical analysis revealed no significant dif­
ferences between prompting methods across datasets (p > .05), though effect size analysis showed notable 
variations in method effectiveness.
Conclusion: Complex prompting techniques do not significantly enhance performance compared to simpler ap­
proaches. Dataset characteristics and model architecture have greater impact, suggesting simpler CoT methods 
may be more effective for clinical applications.
1. Introduction
Large language models (LLMs) have demonstrated notable capabil­
ities across various natural language processing applications, including 
tasks like text generation, summarization, translation, code generation, 
and logical deduction [1–4].. In the medical sector, early initiatives have 
shown promising results, with LLMs capable of composing clinical 
documentation, successfully passing standardized medical examina­
tions, and formulating answers to patient inquiries [5,6]. For a more 
seamless incorporation of LLMs into clinical practice, it is essential to 
understand their reasoning abilities in a clinical context [7]. In 
specialized fields like medicine, utilizing effective prompting techniques 
is vital to provide clear and safe guidance to the model [8].
Prompt engineering is crucial for optimizing LLMs, which involves 
refining prompts to improve LLM performance and communication 
clarity. It is essential for achieving optimal outcomes when working with 
LLMs [9]. The importance of prompt selection, especially in specialized 
domains, cannot be overstated. Prompts act as vital inputs directing 
large language models to produce precise outputs, varying from 
straightforward phrases to more multimodal inputs like images [10]. 
The process of prompt engineering involves strategically crafting textual 
inputs to enhance the model’s output accuracy and consistency signifi­
cantly [11]. This process is essential for maximizing the potential of 
Generative AI models in various applications. Researchers and practi­
tioners can improve the generated content’s quality, relevance, and 
specificity by understanding and leveraging how these models interpret 
different prompts. This, in turn, expands the scope of Generative AI’s 
applicability [12].
Chain-of-thought (CoT) prompting is an innovative technique 
designed to enhance the reasoning capabilities of large language models 
by steering them through a series of logical steps to solve complex 
problems [13]. OpenAI’s o1 model now includes built-in chain-of-­
thought reasoning through reinforcement learning to enhance its 
reasoning capabilities [14]. It provides LLMs with exemplars that not 
* Corresponding author. 1 Gwanak-ro, Gwanak-gu, Seoul, 08826, Republic of Korea.
E-mail address: hgkim@snu.ac.kr (H.-G. Kim). 
Contents lists available at ScienceDirect
Computers in Biology and Medicine
journal homepage: www.elsevier.com/locate/compbiomed
https://doi.org/10.1016/j.compbiomed.2025.110614
Received 28 August 2024; Received in revised form 30 December 2024; Accepted 16 June 2025  
Computers in Biology and Medicine 196 (2025) 110614 
Available online 1 July 2025 
0010-4825/© 2025 The Authors. Published by Elsevier Ltd. This is an open access article under the CC BY license ( http://creativecommons.org/licenses/by/4.0/ ).

# Page 2

only pose a question and its direct answer but also detail the interme­
diate reasoning steps that lead to that conclusion. This method effec­
tively serves as a roadmap, guiding LLMs to mimic this thought process 
for unseen questions, thereby significantly improving their ability to 
tackle various reasoning tasks, from arithmetic to commonsense and 
symbolic reasoning challenges.
This paper investigates how different cognitive characteristics of 
Chain-of-Thought prompting methods affect the performance of large 
language models in medical question-answering tasks. While previous 
studies have explored LLMs’ potential in medicine, including clinical 
documentation and medical question-answering [5,6,15–18], our study 
extends this analysis by evaluating CoT-based prompting techniques 
across both clinical and non-clinical datasets. We specifically incorpo­
rated logical reasoning datasets to assess models’ ability to perform 
complex reasoning beyond simple pattern matching, addressing the 
limitations of clinical-only evaluations. Through API-based access to 
cost-effective LLMs, we evaluated our methods across diverse medical 
contexts while emphasizing logical reasoning capabilities, ensuring our 
findings are robust and generalizable for practical implementation in 
medical AI systems [19].
Our primary objectives are. 
- To evaluate and compare the effectiveness of different CoT 
prompting methods in enhancing LLM performance in medical 
question-answering tasks, focusing on practical applications.
- To examine how these prompting methods perform across diverse 
medical contexts, from theoretical clinical knowledge to practical 
real-world data.
- To evaluate and identify effective prompting strategies that enhance 
LLM performance in clinical knowledge comprehension and complex 
medical reasoning tasks, thereby contributing to the standardization 
of prompt engineering practices in medical AI applications.
2. Methods
2.1. Prompt design
We designed several techniques based on the Chain-of-thought (CoT) 
approach: Traditional CoT [13,17], ReAct CoT [20], Interactive CoT, 
and Self-Consistency [21]. Traditional CoT induces a step-by-step 
approach to guide the model’s responses. ReAct CoT integrates 
reasoning and acting in a three-step cycle of thought (problem analysis), 
action (information retrieval or task execution), and observation 
(outcome evaluation), cycling through these steps until it finds the final 
answer. Interactive CoT was designed to examine the model’s meta­
cognitive capabilities, focusing on its ability to monitor its reasoning 
process, track the evolution from initial thoughts to conclusions, and 
recognize uncertainties while requesting additional information when 
needed. Self-consistency CoT generates multiple reasoning paths and 
selects the most consistent answer through consensus, ensuring model 
outputs remain coherent and consistent across multiple attempts, 
enhancing reliability. While ReAct focuses on a single reasoning path 
with integrated actions, Self-Consistency emphasizes the convergence of 
several reasoning trajectories. These CoT-based techniques were devel­
oped to improve model performance and create effective prompts 
tailored to domain-specific question and answering tasks (Table 1).
We collaborated with ChatGPT to develop prompt methods, which 
allowed us to create effective prompts while reflecting the unique 
characteristics of the medical field. For instance, to create the ReAct 
method, we prompted ChatGPT with: ’Make various versions of the 
prompt templates to guide the model through the ReAct prompting (Wei 
et al., 2022) method to solve medical questions and answer tasks. Let’s 
think step by step.’ ChatGPT would generate several candidate tem­
plates following the ReAct structure when given this prompt. For 
example, a diagnostic reasoning template would be structured as: 
“Problem Statement” identifying the given symptoms, “Step-by-Step 
Reasoning” analyzing primary and secondary symptoms and consid­
ering potential causes, “Action” determining what additional informa­
tion to request, and “Answer” suggesting the most likely diagnosis.
Another example would be a treatment-focused template that fol­
lows similar steps: stating the diagnosis, reasoning through treatment 
options while considering patient factors, recommending the most 
appropriate treatment, and justifying the final treatment plan. From 
these candidate templates, we selected and customized the most suitable 
one to align with our experimental requirements and ensure effective 
responses from the LLM. A basic prompt template was created to instruct 
the model and require a specific format (Table 2). This template corre­
sponds to Control in this experiment to be compared with the different 
types of techniques, and it also works as a default prompt template.
Table 1 
A template of prompt engineering for the study.
Template
{Prompt Method}
CAPITALIZED WORDS are placeholders.
Fill in the placeholders with your rationale and answer (option).
The answer must be a single letter (A,B,C,D, or E).
Question: {question}
Options: {options}
Rationale: <RATIONALE>
Answer: <ANSWER>
Note: The control technique was implemented without the {Prompt Method} part, while maintaining the same basic structure.
Table 2 
Prompt methods.
Methods
Brief Explanation
Prompt
Traditional 
CoT
Simplified chain of thought 
process
Let’s deduce the correct 
response step by step.
ReAct CoT
Cycle through reasoning and 
action until the final answer is 
reached
State your question and act to 
uncover information. Observe 
and analyze the outcome, then 
reflect on these insights step by 
step. Based on your reflection 
determine your next logical 
step.
Interactive 
CoT
Interactive update of thoughts 
to conclude
Identify the question and state 
your initial thought. Gather 
information related to it and 
update your thinking step by 
step. Keep interactive until you 
have a complete answer.
Self- 
Consistency 
CoT
Explore different paths to solve 
problems, reflect to identify 
the best answer and document 
the process for better decision- 
making
Define your question, search for 
diverse solutions. Explore 
different reasoning paths, 
reflect on outcomes, and 
document and analyze each 
reasoning step for self- 
consistency in decision making.
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
2

# Page 3

2.2. Dataset
This study evaluates three distinct categories of datasets: medical 
board exams, question answering using real-world clinical notes, non- 
clinical reasoning tasks, and multilingual tasks (Table 3), all struc­
tured in a multiple-choice question-answering format (Table 1). To 
ensure robustness and generalizability across diverse contexts, we 
selected datasets that represent a wide range of reasoning challenges. In 
the clinical domain, we utilize the MedQA dataset, which comprises 
standardized medical board examination questions from the United 
States, designed to assess physicians’ theoretical knowledge and clinical 
decision-making capabilities across various aspects of medical practice 
[22]. Additionally, MedMCQA incorporates clinical reasoning questions 
derived from medical entrance examinations, specifically targeting 
problem-solving abilities in medical contexts [23]. The clinical assess­
ment is further enhanced by EHRNoteQA, which consists of over 960 
questions based on MIMIC-IV discharge summaries, evaluating the 
comprehension and analysis of real-world clinical scenarios [24,25,26].
To ensure comprehensive linguistic coverage, we incorporate 
MMedBench, selecting Spanish and Chinese datasets due to their status 
as widely spoken languages. The Spanish dataset is derived from Head- 
QA [27], which consists of questions from Spain’s healthcare system 
professional entry exams, while the Chinese dataset is sourced from 
MedQA questions. These datasets, though different in origin and focus, 
provide a diverse representation of medical knowledge across languages 
[28].
To compare the effects of different prompting methods on nonmed­
ical reasoning abilities, we employ GPQA, which consists of graduate- 
level questions across the domains of biology, physics, and chemistry 
[29]. This is complemented by BBH (Big Bench Hard), which presents 
challenging tasks focusing on multi-step reasoning and causal judgment 
[30]. These datasets were chosen to assess complex reasoning capabil­
ities beyond medical contexts. The reasoning assessment is further 
strengthened by MMLU, which evaluates formal logic, critical thinking 
through logical fallacies, and general knowledge application [31]. 
Additionally, to manage computational resources efficiently, we 
randomly sampled 1000 entries from MedMCQA and 500 entries from 
MMedBench using a fixed random seed for reproducibility.
2.3. Model setting and automated QA framework
In our automated QA framework, we employed OpenAI and Google’s 
generative APIs to evaluate various prompting methods for GPT-4o- 
mini, GPT-3.5-turbo, o1-mini, Gemini-1.5-Flash, and Gemini-1.0-Pro. 
The temperature was set to 0 for all models, except the o1-mini, 
which has a fixed temperature of 1. Additionally, we implemented a 
7-s delay between API calls to comply with rate limits. The framework 
processes questions iteratively through concurrent execution, handling 
each dataset and prompt method efficiently. The framework operates 
through a sequential data processing pipeline, selecting a prompt 
method, executing question-answering tasks, and generating the final 
output (Figs. 1 and 2).
3. Result
To rigorously evaluate the effectiveness of prompt engineering 
techniques across diverse medical and reasoning tasks, we first compiled 
comprehensive performance metrics for each combination of models, 
datasets, and prompt methods (Table 4). These accuracy scores served as 
the foundation for our subsequent statistical analyses. We then imple­
mented a comprehensive three-stage statistical framework. First, we 
conducted normality testing using the Shapiro-Wilk test to determine 
the appropriate statistical methods for each dataset. This guided our 
choice between parametric one-way ANOVA and non-parametric Krus­
kal-Wallis analyses. Second, we performed detailed performance anal­
ysis using bootstrap confidence intervals for robust estimation of 
performance metrics, implementing False Discovery Rate (FDR) 
correction to control for multiple comparisons while maintaining sta­
tistical power. Finally, we calculated Cohen’s d effect sizes to quantify 
the practical significance of performance differences between prompt 
engineering techniques relative to the Control method, with effect sizes 
categorized as small (|d| ≤0.5), medium (0.5 < |d| ≤0.8), or large (|d| 
> 0.8).
3.1. Overall performance metrics
Table 4 presents the accuracy scores across all experimental condi­
tions, revealing notable performance variations. In clinical tasks, accu­
racy ranged from 58.14 % to 89.98 % (95 % CI [54.47, 91.83]), with 
EHRNoteQA showing consistently higher scores (M = 89.98 %, 95 % CI 
[88.13, 91.83]) across all models and prompt methods. MedQA (M =
61.00 %, 95 % CI [54.33, 67.67]) and MedMCQA (M = 58.14 %, 95 % CI 
[54.47, 61.81]) showed lower but stable performance. Non-clinical tasks 
demonstrated wider variability, with GPQA showing the lowest overall 
accuracy (M = 39.72 %, 95 % CI [35.46, 43.99]) while MMLU logical 
fallacies achieved notably higher scores (M = 80.68 %, 95 % CI [78.81, 
82.55]). These baseline performance metrics provided the foundation 
for our subsequent statistical analyses examining the effects of different 
prompting techniques and model architectures.
3.2. Statistical framework and distribution analysis
The Shapiro-Wilk test revealed distinct distribution patterns across 
datasets. Clinical datasets predominantly exhibited normal distribu­
tions: MedQA (W = 0.967,p = .125), MedMCQA (W = 0.972,p = .183), 
and EHRNoteQA (W = 0.981,p = .476). For non-clinical tasks, MMLU- 
formal_logic (W = 0.901,p < .001), MMLU-logical_fallacies (W =
0.913,p < .01), and MMLU-global_facts (W = 0.922,p < .01) showed 
non-normal distributions. This distribution heterogeneity necessitated 
an adaptive statistical approach, employing ANOVA for normally 
distributed datasets and Kruskal-Wallis tests for non-normal distribu­
tions, with FDR correction for multiple comparisons.
3.3. Model performance analysis
Model performance analysis revealed significant variations across 
architectures. The o1-mini achieved the highest overall performance (M 
= 73.93 %,SD = 13.53, 95 % CI [70.05, 77.82]), followed by GPT-4o- 
mini (M = 67.24 %,SD = 17.16, 95 % CI [62.32, 72.17]), and Gemini- 
1.5-Flash (M = 64.47 %,SD = 18.38, 95 % CI [59.19, 69.74]). Lower 
performances were observed in GPT-3.5-turbo (M = 57.20 %,SD =
19.09, 95 % CI [51.72, 62.68]) and Gemini-1.0-pro (M = 56.83 %,SD =
17.56, 95 % CI [51.79, 61.87]). Compared to GPT-3.5-turbo, o1-mini 
demonstrated consistently large positive effects across all datasets (d =
2.829 to 15.071), while GPT-4o-mini showed substantial improvements 
(d = 0.836 to 15.087). Gemini-1.5-Flash maintained moderate to large 
positive effects (d = 0.293 to 7.498), whereas Gemini-1.0-pro often 
showed negative effects (d = −1.293 to −0.412) except in specific non- 
clinical tasks. These performance variations across models and datasets 
Table 3 
Dataset characteristics.
Category
Dataset
Size 
(k)
Domain
Clinical
MedQA
1.27k
Medical License
MedMCQA
1.00k
Clinical Reasoning
EHRNoteQA (MIMIC- 
IV)
0.96k
Real-world Clinical 
Documentation
Multilingual
MMedBench
0.50k
Spanish
0.50k
Chinese
Non-clinical
GPQA
0.45k
Science
MMLU
0.50k
Logic and Facts
Big Bench Hard
0.18k
Causal Judgment
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
3

# Page 4

are visualized in Fig. 3, highlighting the consistent superiority of o1- 
mini and the varying effectiveness of different models across task 
categories.
3.4. Dataset-specific performance
In clinical tasks, EHRNoteQA demonstrated superior performance 
Fig. 1. Flow diagram of the study.
Fig. 2. Iterative QA evaluation framework.
Table 4 
Comprehensive performance of LLMs and prompt methods.
Model
Prompt
MedQA
Med 
MCQA
EHR 
NoteQA
GPQA
BBH
MMLU 
(formal 
logic)
MMLU 
(logical 
fallacies)
MMLU 
(global 
facts)
MMedBench 
(Spanish)
MMedBench 
(Chinese)
GPT-4o- 
mini
TradCoT
70.50 %
68.00 %
92.93 %
37.30 %
64.70 %
42.10 %
82.20 %
60 %
89.60 %
69.40 %
ReActCoT
56.20 %
66.10 %
93.14 %
39.30 %
68.40 %
41.30 %
84 %
62 %
86.90 %
70 %
SelfConsistencyCoT
63.50 %
63.30 %
92.72 %
42.00 %
67.40 %
42.10 %
82.80 %
64 %
88.20 %
68.60 %
InteractiveCoT
58.10 %
61.70 %
91.37 %
34.40 %
64.20 %
38.90 %
84 %
62 %
87.80 %
69.60 %
Control
73.40 %
67 %
93.35 %
40.00 %
68.40 %
45.20 %
83.40 %
59 %
90.20 %
71.40 %
GPT- 
3.5- 
turbo
TradCoT
63.30 %
60 %
87.63 %
23.00 %
58.30 %
35.70 %
76.70 %
50 %
78.90 %
53.20 %
ReActCoT
59.20 %
57.40 %
87.84 %
25 %
65.20 %
39.70 %
75.50 %
44 %
80.70 %
52.60 %
SelfConsistencyCoT
60.60 %
56 %
87.42 %
25 %
59.90 %
36.50 %
75.50 %
32 %
79.10 %
53 %
InteractiveCoT
27.70 %
39.20 %
87.32 %
24.00 %
59.40 %
38.10 %
66.90 %
45 %
77.90 %
55 %
Control
61.30 %
59.30 %
87.53 %
27.00 %
54.50 %
42.10 %
78.50 %
54 %
81.70 %
54.80 %
o1-mini
TradCoT
85 %
68.40 %
91.16 %
52.70 %
67.90 %
61.10 %
84.70 %
64 %
93.20 %
79 %
ReActCoT
83.10 %
68 %
89.71 %
49.10 %
67.40 %
55.60 %
84 %
61 %
92.60 %
77.80 %
SelfConsistencyCoT
85 %
69.30 %
89.40 %
52 %
68.40 %
59.50 %
83.40 %
57 %
93.40 %
75.20 %
InteractiveCoT
84.10 %
69.20 %
91.37 %
48.90 %
67.40 %
64.30 %
82.80 %
64 %
93 %
75.40 %
Control
85.30 %
70.30 %
92.10 %
54.50 %
63.60 %
61.90 %
86.50 %
61 %
93.80 %
79.20 %
Gemini- 
1.5- 
Flash
TradCoT
61.60 %
53 %
97.40 %
52.20 %
68.50 %
44.40 %
82.20 %
50 %
88.80 %
71.10 %
ReActCoT
61.40 %
50.20 %
97.61 %
36.80 %
57.80 %
47.60 %
85.30 %
44 %
87.60 %
75.10 %
SelfConsistencyCoT
60 %
52.20 %
97.92 %
45.50 %
65.80 %
41.30 %
84 %
47 %
88.80 %
61.80 %
InteractiveCoT
44.50 %
49.10 %
79.63 %
26.60 %
58.80 %
47.60 %
82.20 %
52 %
89.80 %
59.20 %
Control
62 %
59 %
93.56 %
52 %
71.10 %
44.40 %
83.40 %
48 %
88.60 %
74.90 %
Gemini- 
1.0- 
pro
TradCoT
52.90 %
50.80 %
83.26 %
45.30 %
59.90 %
39.70 %
76.10 %
52 %
78.70 %
62.20 %
ReActCoT
47.10 %
45.40 %
86.90 %
30.80 %
54.50 %
36.50 %
75.50 %
45 %
77.70 %
30.50 %
SelfConsistencyCoT
51.60 %
47.20 %
86.90 %
39.70 %
62.60 %
38.10 %
82.20 %
40 %
77.90 %
61.80 %
InteractiveCoT
31.80 %
48.40 %
87.63 %
44.20 %
59.90 %
37.30 %
79.10 %
51 %
78.30 %
59.20 %
Control
35.80 %
55 %
83.68 %
45.80 %
56.10 %
37.30 %
76.10 %
49 %
76.70 %
30.30 %
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
4

# Page 5

(M = 89.98 %, SD = 4.40, 95 % CI [88.13, 91.83]), significantly out­
performing both MedQA (M = 61.00 %, SD = 15.84, 95 % CI [54.33, 
67.67]) and MedMCQA (M = 58.14 %, SD = 8.70, 95 % CI [54.47, 
61.81]). In non-clinical tasks, MMLU logical fallacies achieved the 
highest performance (M = 80.68 %, SD = 4.43, 95 % CI [78.81, 82.55]), 
while GPQA showed lower performance (M = 39.72 %, SD = 10.12, 95 
% CI [35.46, 43.99]). In multilingual tasks, Spanish language tasks (M =
85.60 %, SD = 5.93, 95 % CI [83.10, 88.09]) performed better than 
Chinese tasks (M = 63.61 %, SD = 12.98, 95 % CI [58.14, 69.08]).
3.5. Prompt engineering effectiveness and effect sizes
In our analysis, Control serves as a baseline prompt method that 
provides basic instructions without any specific reasoning technique. 
Each CoT method’s effectiveness is measured through Cohen’s d effect 
sizes calculated against this Control condition, enabling standardized 
comparison across different datasets. Statistical analysis revealed no 
significant differences between prompt engineering techniques after 
FDR correction across datasets (MedQA: F = 0.875,p = .496; MedMCQA: 
F = 0.618,p = .655; EHRNoteQA: F = 0.482,p = .748). Traditional CoT 
demonstrated the most consistent performance (M = 65.61 %,SD =
Fig. 3. Performance comparison of different datasets, models, and prompts.
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
5

# Page 6

17.17, 95 % CI [60.68, 70.54]), while Interactive CoT showed the lowest 
overall performance (M = 61.59 %,SD = 19.21, 95 % CI [56.07, 67.10]).
Effect size analysis revealed varying impacts across different con­
texts: Traditional CoT maintained stable performance compared to 
Control (d = −0.301 to 0.308, lowest in MMLU logical fallacies and 
highest in Chinese tasks). Interactive CoT showed consistent negative 
effects (d = −0.905 to −0.566, most pronounced in MedMCQA) and 
ReAct CoT demonstrated variable effects ranging from medium negative 
to small positive (d = −0.760 to 0.229, lowest in GPQA and highest in 
EHRNoteQA). SelfConsistency CoT showed moderate variability (d =
−0.623 to 0.362, lowest in MMLU global facts and highest in BBH causal 
judgement) These effect sizes indicate performance deviations from the 
Control method, with positive values suggesting improvement and 
negative values indicating performance decline relative to the basic 
prompting approach. The distribution of performance across different 
prompt engineering techniques is illustrated in Fig. 4, demonstrating the 
relative stability of Traditional CoT compared to other methods.
4. Discussion
This research evaluates the effectiveness of various Chain-of- 
Thought (CoT) prompting methods in enhancing large language 
models’ performance across clinical and non-clinical reasoning tasks. 
Our study found that prompting strategies did not yield statistically 
significant performance differences across datasets. Instead, model ar­
chitecture emerged as a key determinant, with o1-mini achieving the 
Fig. 4. Distribution of performance across prompt methods.
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
6

# Page 7

highest overall performance, followed by GPT-4o-mini and Gemini-1.5- 
Flash. The performance patterns across different task types demonstrate 
that base model capabilities and dataset characteristics, rather than 
prompting techniques, are the crucial factors in determining effective­
ness. This suggests that for real-world clinical applications, the focus 
should be on selecting appropriate models rather than utilizing complex 
prompting strategies. Interactive CoT consistently showed negative ef­
fects across medical knowledge tasks and real-world datasets, suggesting 
that complex interactive approaches may not be optimal for clinical 
applications. In contrast, ReAct CoT demonstrated variable performance 
between question-answering linked to discharge summaries and scien­
tific reasoning tasks. These differences suggest that the complexity 
introduced by advanced prompting methods may not always translate 
into better outcomes for certain task types, particularly in medical 
contexts where clarity and reliability are crucial.
Traditional CoT maintained stable performance across datasets by 
following a straightforward sequential reasoning path. In contrast, 
Interactive CoT’s attempt to leverage metacognitive abilities - moni­
toring reasoning processes, tracking evolution of thoughts, and recog­
nizing uncertainties - often resulted in lower performance, particularly 
in complex reasoning tasks. This was evident in medical knowledge 
tasks, where Interactive CoT showed considerable performance drops in 
particularly MedMCQA. Similarly, ReAct CoT’s integration of reasoning 
and acting in a three-step cycle showed variable performance across 
different tasks, suggesting that the additional complexity of action steps 
may interfere with the core reasoning process. These patterns indicate 
that while Traditional CoT provides a stable foundation through its 
simple, direct reasoning approach, both Interactive CoT and ReAct 
CoT’s more sophisticated mechanisms may introduce unnecessary 
complexity that interferes with the model’s reasoning process, particu­
larly in tasks requiring sophisticated medical knowledge and scientific 
reasoning.
Our results demonstrate that while there were no statistically sig­
nificant differences between prompting methods, prompt engineering 
strategies affect performance differently based on their complexity level, 
with simpler approaches often yielding more reliable outcomes across 
different clinical reasoning tasks. This insight is particularly relevant for 
applications such as clinical decision support systems, medical educa­
tion, and clinical documentation [32,33–36].
Previous research has shown that generalist language models like 
GPT-4 and GPT-3.5 can perform well in answering medical questions 
without extensive fine-tuning [15,16]. However, the challenge of 
interpretability in applying large language models in medicine, mainly 
due to their black-box nature, has been a significant barrier. Savage et al. 
(2024) addressed this challenge by examining LLMs’ ability to simulate 
clinical reasoning in diagnostic cases [17]. Their study revealed that 
GPT-4 could successfully replicate physicians’ diagnostic reasoning 
processes while maintaining diagnostic accuracy through specialized 
diagnostic reasoning prompts. This approach presents a substantial leap 
towards integrating LLMs into clinical settings by providing an inter­
pretable rationale for their recommendations, aiding physicians in 
assessing the trustworthiness of LLM responses for patient care.
Another study by Wang et al. (2024) examined the effectiveness of 
prompt engineering strategies in medical applications [18]. Their sys­
tematic evaluation of LLMs’ consistency with established medical 
guidelines for treating osteoarthritis revealed that specific prompting 
methods could significantly improve the accuracy and reliability of AI 
responses. Their findings particularly emphasized how different 
prompting strategies could affect the model’s adherence to 
evidence-based guidelines, demonstrating the critical role of appro­
priate prompt engineering in enhancing LLMs’ performance for medical 
applications. While Savage et al. (2024) and Wang et al. (2024) sug­
gested that specialized prompt strategies could enhance LLM perfor­
mance in medical domains, our findings demonstrate that increased 
prompt complexity does not necessarily guarantee better performance. 
Despite the lack of statistical significance after FDR correction and the 
consistent performance of Traditional CoT suggest that simpler, more 
straightforward reasoning approaches may be more effective in medical 
question-answering.
A particularly notable finding is the impact of dataset characteristics 
on model performance. The high performance on EHRNoteQA demon­
strates the potential of LLMs in real clinical data applications, while the 
lower performance on GPQA reveals limitations in general scientific 
reasoning tasks. The large negative effect size observed with Interactive 
CoT in MedMCQA suggests that complex cognitive approaches may 
actually interfere with core reasoning processes. These findings 
emphasize that in developing clinical decision support systems, 
considering the model’s fundamental capabilities and dataset charac­
teristics may be more crucial than optimizing prompting techniques.
The performance variations among different models provide addi­
tional insights into the relationship between model architecture and 
medical reasoning capabilities. The o1-mini achieved the highest overall 
performance, significantly outperforming other models including GPT- 
4o-mini, particularly excelling in medical licensing exams and main­
taining high performance in multilingual contexts (Spanish and Chi­
nese). This robust performance may be attributed to its reinforcement 
learning-based chain-of-thought capabilities, as o1-mini is specifically 
designed to think through problems by producing a long chain of 
thought before providing answers [14]. In contrast, GPT-4o-mini and 
GPT-3.5-turbo showed more variable performance patterns. While 
GPT-4o-mini demonstrated strong capabilities in complex reasoning 
tasks through its end-to-end multimodal training [37], GPT-3.5-turbo’s 
performance fluctuated across different medical context.
These differences suggest that model training strategies play crucial 
roles in determining performance across various medical reasoning 
tasks, independent of prompting methods. These model-specific differ­
ences were not limited to OpenAI models. Similar variations were 
observed in the Gemini models. Gemini 1.5 Flash, despite being 
designed for efficiency, demonstrates improved performance over 
Gemini 1.0 Pro across many benchmarks, including reasoning and 
knowledge tasks. This is likely due to Gemini 1.5 Flash’s use of parallel 
computation of attention and feedforward components, as well as online 
distillation from the larger Gemini 1.5 Pro model [38,39]. Additionally, 
Gemini 1.5 Flash is trained with higher-order preconditioned methods 
for improved quality. While these advancements show promise for 
medical AI applications, specific comparisons in medical reasoning tasks 
between these models require further investigation.
Recent research by Goh et al. (2024) and Chen et al. (2024) com­
plements our findings, suggesting that the integration of LLMs into 
clinical practice requires more nuanced approaches than simply 
enhancing model performance [32,40]. Based on our experimental re­
sults, we propose the following concrete implementation strategies for 
clinical settings:
First, when developing clinical decision support systems, the focus 
should be on selecting models with strong baseline capabilities rather 
than implementing complex prompting techniques. Our findings with 
o1-mini demonstrate that models trained specifically for sequential 
reasoning perform more reliably in medical contexts. Second, the inte­
gration of LLMs should be tailored to specific clinical tasks. For instance, 
EHRNoteQA results suggest that these systems could be particularly 
effective for clinical documentation and discharge summary analysis, 
while more complex diagnostic reasoning tasks may require different 
approaches. Lastly, the implementation should prioritize transparency 
and interpretability. Traditional CoT’s consistent performance suggests 
that straightforward reasoning paths may be more practical for health­
care professionals to verify and integrate into their workflow.
These implementation strategies should be validated through pilot 
studies in real clinical settings. Future research should focus on how 
LLMs can effectively synergize with healthcare professionals in real 
clinical settings. Rather than concentrating solely on model perfor­
mance, it is crucial to develop implementation strategies that explore 
the practical integration of these models alongside human medical 
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
7

# Page 8

expertise. This approach will help ensure that AI systems complement 
and enhance clinical decision-making processes while maintaining the 
essential role of healthcare professionals.
5. Conclusion
This research examines the effectiveness of different Chain-of- 
Thought prompting methods in enhancing LLMs’ medical reasoning 
capabilities. Our findings reveal that prompting strategies did not yield 
statistically significant performance differences across datasets. Instead, 
model architecture and training strategies emerged as key determinants 
of performance, with o1-mini’s reinforcement learning-based chain-of- 
thought capabilities demonstrating superior capabilities across diverse 
medical contexts. Traditional CoT’s stable performance, particularly in 
clinical datasets linked to real-world clinical notes, suggests that simpler 
prompting approaches may be more reliable for clinical applications.
However, our study has several limitations. First, while our experi­
ments demonstrate the effectiveness of simpler prompting approaches, 
they were conducted in controlled settings that may not fully reflect the 
complexities of real clinical environments. Second, the performance 
variations across different medical contexts suggest that model capa­
bilities and dataset characteristics play more crucial roles than 
prompting strategies. This highlights the need for multidimensional 
evaluation frameworks that consider both technical performance met­
rics and practical clinical implementation challenges.
Based on these findings, we propose that future research should focus 
on two key areas. First, investigating how model selection and concise 
prompting approaches can be optimized for specific clinical tasks, rather 
than pursuing complex prompting strategies. Second, developing 
implementation strategies that effectively integrate LLMs into clinical 
workflows while maintaining the essential role of healthcare pro­
fessionals. This approach will help ensure that LLM-based AI systems 
serve as practical and collaborative tools that create synergistic rela­
tionship between humans and AI, leading to enhanced clinical decision- 
making.
CRediT authorship contribution statement
Sohyeon Jeon: Writing – review & editing, Writing – original draft, 
Visualization, Validation, Supervision, Software, Resources, Project 
administration, Methodology, Investigation, Funding acquisition, 
Formal analysis, Data curation, Conceptualization. Hong-Gee Kim: 
Supervision.
Ethics statement
This research did not involve any human subjects or animal experi­
ments. All data processing and analysis were conducted in accordance 
with ethical research practices and data protection guidelines.
Declaration of competing interest
The authors declare that they have no known competing financial 
interests or personal relationships that could have appeared to influence 
the work reported in this paper.
Acknowledgements
This work was supported by the National Research Foundation of 
Korea (NRF) grant funded by the Korea government(Ministry of Science 
and ICT) (No. RS-2023-00268071).
References
[1] T. Brown, B. Mann, N. Ryder, M. Subbiah, J.D. Kaplan, P. Dhariwal, D. Amodei, 
Language models are few-shot learners, Adv. Neural Inf. Process. Syst. 33 (2020) 
1877–1901.
[2] M. Chen, J. Tworek, H. Jun, Q. Yuan, H.P.D.O. Pinto, J. Kaplan, W. Zaremba, 
Evaluating large language models trained on code, arXiv preprint arXiv: 
2107.03374 (2021).
[3] T. Brants, A. Popat, P. Xu, F.J. Och, J. Dean, Large language models in machine 
translation, in: Proceedings of the 2007 Joint Conference on Empirical Methods in 
Natural Language Processing and Computational Natural Language Learning 
(EMNLP-CoNLL), 2007, June, pp. 858–867.
[4] S. Yao, D. Yu, J. Zhao, I. Shafran, T. Griffiths, Y. Cao, K. Narasimhan, Tree of 
thoughts: deliberate problem solving with large language models, Adv. Neural Inf. 
Process. Syst. 36 (2024).
[5] T.H. Kung, M. Cheatham, A. Medenilla, C. Sillos, L. De Leon, C. Elepa˜no, V. Tseng, 
Performance of ChatGPT on USMLE: potential for AI-assisted medical education 
using large language models, PLoS digital health 2 (2) (2023) e0000198.
[6] A.S. Tejani, M.E. Klontzas, A.A. Gatti, J. Mongan, L. Moy, S.H. Park, C.E. Kahn Jr, 
Updating the checklist for artificial intelligence in medical imaging (CLAIM) for 
reporting AI research, Nat. Mach. Intell. 5 (9) (2023) 950–951.
[7] M. Sushil, V.E. Kennedy, D. Mandair, B.Y. Miao, T. Zack, A.J. Butte, CORAL: 
expert-curated oncology reports to advance language model inference, NEJM AI 
(2024) AIdbp2300110.
[8] J.A. Omiye, H. Gui, S.J. Rezaei, J. Zou, R. Daneshjou, Large language models in 
medicine: the potentials and pitfalls: a narrative review, Ann. Intern. Med. 177 (2) 
(2024) 210–220.
[9] Q. Ye, M. Axmed, R. Pryzant, F. Khani, Prompt engineering a prompt engineer, 
arXiv preprint arXiv:2311.05661 (2023).
[10] K. Zhou, J. Yang, C.C. Loy, Z. Liu, Learning to prompt for vision-language models, 
Int. J. Comput. Vis. 130 (9) (2022) 2337–2348.
[11] J. White, Q. Fu, S. Hays, M. Sandborn, C. Olea, H. Gilbert, D.C. Schmidt, A prompt 
pattern catalog to enhance prompt engineering with chatgpt, arXiv preprint arXiv: 
2302.11382 (2023).
[12] S.S. Bains, J.A. Dubin, D. Hameed, O.C. Sax, S. Douglas, M. Mont, R.E. Delanois, 
Use and application of large language models for patient questions following total 
knee arthroplasty, J. Arthroplast. (2024).
[13] J. Wei, X. Wang, D. Schuurmans, M. Bosma, F. Xia, E. Chi, D. Zhou, Chain-of- 
thought prompting elicits reasoning in large language models, Adv. Neural Inf. 
Process. Syst. 35 (2022) 24824–24837.
[14] OpenAI, o1 system card. https://cdn.openai.com/o1-system-card-20241205.pdf, 
2024.
[15] H. Nori, Y.T. Lee, S. Zhang, D. Carignan, R. Edgar, N. Fusi, E. Horvitz, Can 
generalist foundation models outcompete special-purpose tuning? Case study in 
medicine, arXiv preprint arXiv:2311.16452 (2023).
[16] V. Sorin, E. Klang, M. Sklair-Levy, I. Cohen, D.B. Zippel, N. Balint Lahat, Y. Barash, 
Large language model (ChatGPT) as a support tool for breast tumor board, NPJ 
Breast Cancer 9 (1) (2023) 44.
[17] T. Savage, A. Nayak, R. Gallo, E. Rangan, J.H. Chen, Diagnostic reasoning prompts 
reveal the potential for large language model interpretability in medicine, npj 
Digit. Med. 7 (1) (2024) 20.
[18] L. Wang, X. Chen, X. Deng, H. Wen, M. You, W. Liu, J. Li, Prompt engineering in 
consistency and reliability with the evidence-based guideline for LLMs, npj Digit. 
Med. 7 (1) (2024) 41.
[19] E. Klang, D. Apakama, E.E. Abbott, A. Vaid, J. Lampert, A. Sakhuja, B. 
S. Glicksberg, A strategy for cost-effective large language model use at health 
system-scale, npj Digit. Med. 7 (1) (2024) 320.
[20] S. Yao, J. Zhao, D. Yu, N. Du, I. Shafran, K. Narasimhan, Y. Cao, React: synergizing 
reasoning and acting in language models, arXiv preprint arXiv:2210.03629 (2022).
[21] X. Wang, J. Wei, D. Schuurmans, Q. Le, E. Chi, S. Narang, D. Zhou, Self-consistency 
improves chain of thought reasoning in language models, arXiv preprint arXiv: 
2203.11171 (2022).
[22] D. Jin, E. Pan, N. Oufattole, W.H. Weng, H. Fang, P. Szolovits, What disease does 
this patient have? A large-scale open domain question answering dataset from 
medical exams, Appl. Sci. 11 (14) (2021) 6421.
[23] A. Pal, L.K. Umapathi, M. Sankarasubbu, MedMCQA: a large-scale multi-subject 
multi-choice dataset for medical domain question answering, in: Conference on 
Health, Inference, and Learning, PMLR, 2022, pp. 248–260.
[24] A.E. Johnson, L. Bulgarelli, T.J. Pollard, S. Horng, L.A. Celi, R.G. Mark, MIMIC-IV, 
a freely accessible electronic health record dataset, Sci. Data 10 (1) (2023) 1.
[25] J. Kim, S. Park, M. Lee, H. Shin, EHRNoteQA: a patient-specific question answering 
benchmark for real-world clinical practice using discharge summaries, arXiv 
preprint arXiv:2402.16040 (2024).
[26] A. Johnson, T. Pollard, S. Horng, L.A. Celi, R. Mark, MIMIC-IV-Note: deidentified 
free-text clinical notes, PhysioNet, version 2.2, 2023. https://doi.org/10.13026/ 
1n74-ne17.
[27] D. Vilares, C. G´omez-Rodríguez, HEAD-QA: a healthcare dataset for complex 
reasoning, in: Proceedings of the 57th Annual Meeting of the Association for 
Computational Linguistics, Association for Computational Linguistics, Florence, 
Italy, July 2019, pp. 960–966.
[28] P. Qiu, C. Wu, X. Zhang, W. Lin, H. Wang, Y. Zhang, W. Xie, Towards building 
multilingual language model for medicine, Nat. Commun. 15 (1) (2024) 8384.
[29] D. Rein, B.L. Hou, A.C. Stickland, J. Petty, R.Y. Pang, J. Dirani, S.R. Bowman, 
GPQA: a graduate-level google-proof Q&A benchmark, arXiv preprint arXiv: 
2311.12022 (2024).
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
8

# Page 9

[30] A. Srivastava, A. Rastogi, A. Rao, M. Shoeybi, M. Patwary, K. Keutzer, BIGbench: a 
unified benchmark for social bias in text-to-image generative models, arXiv 
preprint arXiv:2407.15240 (2024).
[31] Y. Wang, H. Zhang, Z. Liu, Y. Chen, X. Wang, MMLU-Pro: a more robust and 
challenging multi-task language understanding benchmark, arXiv preprint arXiv: 
2406.01574 (2024).
[32] E. Goh, R. Gallo, J. Hom, E. Strong, Y. Weng, H. Kerman, J.H. Chen, Large language 
model influence on diagnostic reasoning: a randomized clinical trial, JAMA Netw. 
Open 7 (10) (2024) e2440969.
[33] C.E. Chua, N.L.Y. Clara, M.S. Furqan, J.L.W. Kit, A. Makmur, Y.C. Tham, K. 
Y. Ngiam, Integration of customised LLM for discharge summary generation in 
real-world clinical settings: a pilot study on RUSSELL GPT, The Lancet Regional 
Health–Western Pacific 51 (2024).
[34] E. Brügge, S. Ricchizzi, M. Arenbeck, M.N. Keller, L. Schur, W. Stummer, D. Darici, 
Large language models improve clinical decision making of medical students 
through patient simulation and structured feedback: a randomized controlled trial, 
BMC Med. Educ. 24 (1) (2024) 1391.
[35] P. Hager, F. Jungmann, R. Holland, K. Bhagat, I. Hubrecht, M. Knauer, D. Rueckert, 
Evaluation and mitigation of the limitations of large language models in clinical 
decision-making, Nat. Med. 30 (9) (2024) 2613–2622.
[36] H. Wu, P. Boulenger, A. Faure, B. C´espedes, F. Boukil, N. Morel, A. Bosselut, EPFL- 
MAKE at “discharge me!”: an LLM system for automatically generating discharge 
summaries of clinical electronic health record, in: Proceedings of the 23rd 
Workshop on Biomedical Natural Language Processing, 2024, August, 
pp. 696–711.
[37] A. Hurst, A. Lerer, A.P. Goucher, A. Perelman, A. Ramesh, A. Clark, I. Kivlichan, 
Gpt-4o system card, arXiv preprint arXiv:2410.21276 (2024).
[38] G. Team, P. Georgiev, V.I. Lei, R. Burnell, L. Bai, A. Gulati, B.O. Batsaikhan, Gemini 
1.5: unlocking multimodal understanding across millions of tokens of context, 
arXiv preprint arXiv:2403.05530 (2024).
[39] G. Team, R. Anil, S. Borgeaud, J.B. Alayrac, J. Yu, R. Soricut, L. Blanco, Gemini: a 
family of highly capable multimodal models, arXiv preprint arXiv:2312.11805 
(2023).
[40] D. Chen, R.S. Huang, J. Jomy, P. Wong, M. Yan, J. Croke, S. Raman, Performance 
of multimodal artificial intelligence chatbots evaluated on clinical oncology cases, 
JAMA Netw. Open 7 (10) (2024) e2437711.
S. Jeon and H.-G. Kim                                                                                                                                                                                                                         
Computers in Biology and Medicine 196 (2025) 110614 
9
