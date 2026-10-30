# Page 1

Chang et al. BMC Psychiatry           (2025) 25:28  
https://doi.org/10.1186/s12888-024-06443-2
RESEARCH
Open Access
© The Author(s) 2025. Open Access  This article is licensed under a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 
International License, which permits any non-commercial use, sharing, distribution and reproduction in any medium or format, as long 
as you give appropriate credit to the original author(s) and the source, provide a link to the Creative Commons licence, and indicate if 
you modified the licensed material. You do not have permission under this licence to share adapted material derived from this article or 
parts of it. The images or other third party material in this article are included in the article’s Creative Commons licence, unless indicated 
otherwise in a credit line to the material. If material is not included in the article’s Creative Commons licence and your intended use is not 
permitted by statutory regulation or exceeds the permitted use, you will need to obtain permission directly from the copyright holder. To 
view a copy of this licence, visit http://​creat​iveco​mmons.​org/​licen​ses/​by-​nc-​nd/4.​0/.
BMC Psychiatry
A network analysis of depression and anxiety 
symptoms among Chinese elderly living alone: 
based on the 2017–2018 Chinese Longitudinal 
Healthy Longevity Survey (CLHLS)
Ze Chang1†, Yunfan Zhang1†, Xiao Liang1, Yunmeng Chen1, Chunyan Guo1, Xiansu Chi1, Liuding Wang1, 
Xie Wang2, Hong Chen2, Zixuan Zhang1, Longtao Liu1, Lina Miao1* and Yunling Zhang1* 
Abstract 
Background  Elderly individuals living alone represent a vulnerable group with limited family support, making them 
more susceptible to mental health issues such as depression and anxiety. This study aims to construct a network 
model of depression and anxiety symptoms among older adults living alone, exploring the correlations and centrality 
of different symptoms. The goal is to identify core and bridging symptoms to inform clinical interventions.
Methods  Using data from the 2018 Chinese Longitudinal Healthy Longevity Survey (CLHLS), this study constructed 
a network model of depression and anxiety symptoms among elderly individuals living alone. Depression and anxiety 
symptoms were assessed using the Center for Epidemiologic Studies Depression Scale-10 (CESD-10) and the Gen-
eralized Anxiety Disorder Scale-7 (GAD-7), respectively. A Gaussian Graphical Model (GGM) was employed to build 
the symptom network, and the Fruchterman-Reingold algorithm was used for visualization, with the thickness 
and color of the edges representing partial correlations between symptoms. To minimize spurious correlations, 
the Least Absolute Shrinkage and Selection Operator (LASSO) method was applied for regularization, and the opti-
mal regularization parameters were selected using the Extended Bayesian Information Criterion (EBIC). We further 
calculated Expected Influence (EI) and Bridge Expected Influence (Bridge EI) to evaluate the importance of symptoms. 
Non-parametric bootstrap methods were used to assess the stability and accuracy of the network.
Results  The Network centrality analysis revealed that GAD2 (Uncontrollable worry) and GAD4 (Trouble relaxing) 
exhibited the highest strength centrality (1.128 and 1.102, respectively), indicating their significant direct associations 
with other symptoms and their roles as core nodes in the anxiety symptom network. Other highly central nodes, such 
as GAD1 (Nervousness or anxiety) and GAD3 (Generalized worry), further underscore the dominance of anxiety symp-
toms in the overall network. Betweenness centrality results highlighted GAD1 (Nervousness or anxiety) and GAD2 
(Uncontrollable worry) as critical bridge nodes facilitating information flow between different symptoms, while CESD3 
(Feeling depressed) demonstrated a bridging role across modules. Weighted analyses further confirmed the central 
†Ze Chang and Yunfan Zhang are co-first authors.
*Correspondence:
Lina Miao
18811367899@163.com
Yunling Zhang
yunlingzhang2004@126.com
Full list of author information is available at the end of the article

# Page 2

Page 2 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
importance of GAD2 (Uncontrollable worry) and GAD4 (Trouble relaxing). Additionally, the analysis showed gender 
differences in the depression-anxiety networks of elderly individuals living alone.
Conclusion  This study, through network analysis, uncovered the complex relationships between depression 
and anxiety symptoms among elderly individuals living alone, identifying GAD2 (Uncontrollable worry) and GAD4 
(Trouble relaxing) as core symptoms. These findings provide essential insights for targeted interventions. Future 
research should explore intervention strategies for these symptoms to improve the mental health of elderly individu-
als living alone.
Keywords  Elderly living alone, Depression and anxiety, Network analysis, Core symptoms
Introduction
Currently, the mental health issues of the elderly have 
garnered widespread attention in recent years, particu-
larly concerning the depression and anxiety experienced 
by elderly individuals living alone [1]. As the trend of 
population aging intensifies in China, an increasing num-
ber of seniors are choosing or being compelled to live 
independently [2]. In fact, due to factors such as social 
support [3] and substance abuse [4], elderly individuals 
living alone often face more severe mental health issues, 
including anxiety, depression, feelings of loneliness, 
and a sense of worthlessness [5]. The lack of daily social 
interaction and support makes these seniors particularly 
susceptible to feelings of isolation, which are significant 
contributors to depression and anxiety [6, 7]. Research 
indicates that elderly individuals living alone are more 
likely to experience loneliness and social isolation com-
pared to their counterparts who live with others [8]. This 
sense of loneliness not only affects their emotional state 
but may also lead to a deterioration in physical health, 
severely impacting both the psychological and physiolog-
ical well-being of elderly individuals living independently 
[9].
A substantial body of research has examined the rela-
tionship between living alone and the prevalence of 
depression and anxiety. Studies indicate that among 
the elderly population in China, individuals living alone 
face a significantly higher risk of developing depression 
compared to their non-living-alone counterparts [10]. 
Moreover, living alone may serve as a straightforward 
yet effective predictive indicator for identifying high-risk 
groups for depression among the elderly [11]. A large-
scale study conducted within the UK population has also 
confirmed that living alone is a high-risk factor for the 
onset of depression [12]. Anxiety, as one of the predomi-
nant psychological challenges faced by elderly individu-
als living in solitude, frequently coexists with depression. 
Research indicates that seniors residing alone often 
encounter anxiety stemming from factors such as the 
fear of isolation, physical deterioration, pervasive feelings 
of loneliness, and financial hardships [13]. A systematic 
review conducted by Ciuffreda et  al. further suggests 
that feelings of loneliness are intricately linked to anxi-
ety and depressive symptoms among the elderly during 
the COVID-19 pandemic [14].Moreover, due to com-
munication barriers, self-neglect, and the societal stigma 
associated with mental disorders, elderly individuals 
living alone may experience significant delays in access-
ing healthcare services [15]. These factors collectively 
contribute to a deterioration in quality of life and an 
escalation in mortality rates among seniors living inde-
pendently [16]. Consequently, the issues of depression 
and anxiety among elderly individuals living alone repre-
sent a multifaceted and pressing social concern. A thor-
ough understanding of the intrinsic relationship between 
depression and anxiety within this demographic is essen-
tial for formulating effective prevention and intervention 
strategies.
Network analysis is an emerging data analysis method 
that represents the characteristics and information of 
a system in the form of a network. Networks consist of 
"nodes" and "edges" used to observe the interactions and 
associations between factors of interest. The network 
theory of mental disorders is based on network analy-
sis methods [17]. It conceptualizes mental disorders as 
symptom networks, where causal relationships among 
symptoms and their dynamic interactions lead to the 
onset and development of mental disorders [18]. For 
instance, in treating individuals with depression, symp-
toms exhibit causal relationships, allowing for the pre-
diction of dynamic changes in related symptoms through 
the alleviation of one symptom [19]. Network analysis of 
mental disorders enables the identification of core symp-
toms that are most closely related to surrounding symp-
toms and bridge symptoms that link different mental 
disorders. These critical symptoms are essential for main-
taining the complex network and may play unique roles 
in diagnosis, prediction, and treatment [18, 20].
Despite some existing studies on depression and 
anxiety in elderly individuals living alone, several 
limitations remain [21–23]. Most research on men-
tal disorders in the elderly has focused on anxiety or 
depression as overarching categories, neglecting the 
interrelations and mutual influences between clinical

# Page 3

Page 3 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	
symptoms, thereby failing to highlight the core symp-
toms within the multifaceted presentations of mental 
disorders. Many studies employ relatively traditional 
methods, such as basic quantitative surveys or case 
reports, without fully leveraging modern data analy-
sis techniques [11, 24]. Network analysis specifically 
targeting anxiety and depression symptoms in elderly 
individuals living alone is scarce. Therefore, this study 
applies network analysis to uncover the relationships 
between depression and anxiety symptoms in elderly 
individuals living alone in China. By identifying core 
symptoms and bridge symptoms within the symptom 
network, this research aims to provide a comprehen-
sive understanding of the complexity of depression and 
anxiety issues in this population, and explore potential 
intervention strategies.
Materials and methods
Study participants
This study utilizes data from the 2017–2018 wave of 
the Chinese Longitudinal Healthy Longevity Sur-
vey (CLHLS). The CLHLS was initiated in 1998 and 
has since conducted follow-up surveys in 2000, 2002, 
2005, 2008–2009, 2011–2012, 2014, and 2017–2018 
across 23 provinces in China, continuously recruiting 
new participants to maintain a consistent sample size 
[25]. The survey process is carried out by well-trained 
professionals using structured questionnaires cover-
ing demographic characteristics, socioeconomic sta-
tus, daily living abilities, physical and mental health, 
cognitive function, lifestyle factors, and social sup-
port [26]. The CLHLS study received ethical approval 
from the Peking University Institutional Review Board 
(IRB00001052-13074), and written informed consent 
was obtained from each participant or their author-
ized representative. Participation in the CLHLS is vol-
untary, and respondents are free to withdraw from the 
study at any time without any consequences.
In this study, we focused on elderly individuals liv-
ing alone, defined as those who do not have a spouse 
or any other family members living with them in the 
same household. These individuals were classified 
as "living alone" based on their self-reported living 
arrangements in the questionnaire. Participants below 
the age of 60 were excluded to ensure that the study 
sample conforms to the established definition of the 
elderly population. Furthermore, individuals with over 
20% missing data on critical variables (such as GESD-
10 and GAD-7) were also excluded from the analysis. 
Data from a total of 2028 elderly individuals living 
alone were included in this study.
Survey instruments
This study used the 10-item version of the Center for Epi-
demiologic Studies Depression Scale (CESD-10) to assess 
depression among elderly individuals living alone [27]. 
The scale has a Cronbach’s α coefficient of 0.809, indi-
cating good internal consistency. The CESD-10 encom-
passes ten items related to insomnia, feelings of sadness, 
hopelessness, and depression. Its validity and reliability 
have been extensively validated within the Chinese popu-
lation, establishing it as a crucial instrument for assess-
ing depressive symptoms among this demographic [28]. 
Scores range from 0 to 30, with higher scores indicating 
more severe depression. A CESD-10 score of ≥ 11 is con-
sidered indicative of depressive symptoms, while a score 
of < 10 suggests no significant depressive symptoms. To 
evaluate anxiety levels among elderly individuals living 
alone, this study employed the Generalized Anxiety Dis-
order 7-item scale (GAD-7) [29]. The GAD-7 comprises 
seven items that cover various aspects of generalized 
anxiety symptoms. Scores range from 0 to 21, with higher 
scores indicating more severe anxiety symptoms. A 
GAD-7 score > 5 is considered indicative of anxiety symp-
toms. The Chinese versions of both the CESD-10 and 
GAD-7 scales have been validated and shown to possess 
good reliability and validity [30]. These scales are widely 
used in assessing mental disorders among the elderly in 
China [31, 32].
Network analysis
In this study, we employed a Gaussian Graphical Model 
(GGM) to construct a network of depressive and anxi-
ety symptoms among elderly individuals living alone 
[33]. We preprocessed the data, which included handling 
missing values and standardizing the scores. We visual-
ized the symptom network using the fruchterman-rein-
gold algorithm [34], where the thickness and color of the 
edges represent the partial correlations between symp-
toms. To eliminate spurious correlations, we applied 
the LASSO method for regularization and utilized the 
Extended Bayesian Information Criterion (EBIC) to 
select the optimal regularization parameter [35, 36]. The 
core symptoms of the network are primarily measured 
using centrality indices, with higher centrality scores 
indicating a more pivotal role of the symptoms. The cen-
trality indices include strength centrality, bridge central-
ity, and closeness centrality, all of which serve to assess 
the significance of nodes within the network. Strength 
centrality refers to the sum of the absolute values of the 
connection strengths between a particular symptom 
and other symptoms. Closeness centrality measures 
the average shortest path length from a symptom to all 
other symptoms. Bridge centrality assesses the extent to

# Page 4

Page 4 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
which a symptom acts as a bridge in the shortest paths 
between other symptoms within the network. A higher 
bridge centrality indicates that the symptom plays a more 
crucial role in connecting other symptoms, serving as a 
key mediator in the transmission of symptoms. We calcu-
lated the bridge expected influence to evaluate the bridg-
ing effect across symptom clusters. The barrat’s strength 
and onnela’s weighted measure are utilized in weighted 
network analysis to identify significant nodes within local 
networks. Additionally, we employed a non-parametric 
bootstrap method to evaluate the stability and accuracy 
of the network, identifying core and bridging symptoms 
within the domains of depression and anxiety.
Result
Baseline characteristics
A total of 2,028 older adults living alone were included in 
the analysis. The average age was 84.28 years (SD = 9.47), 
with 775 male and 1,253 female. The overall mean score 
for the CESD-10 was 8.21 (SD = 4.73), and the mean 
score for the GAD-7 was 1.61 (SD = 3.00). The mean val-
ues and standard deviations for all CESD-10 and GAD-7 
items are presented in Table 1.
Symptom network analysis of depression and anxiety 
among older adults living alone
The network structure of depression and anxiety symp-
toms among older adults living alone is illustrated in 
Fig.  1. A circular pie chart is used to represent node 
predictability, with an average predictability of 0.433 
(ranging from 0.199 to 0.701, see Table  1). Within the 
depression symptom network, the strongest associations 
were observed between CESD1 (Feeling bothered) and 
CESD3 (Feeling depressed), followed by CESD2 (Trou-
ble focusing) and CESD4 (Trouble doing anything), as 
well as CESD5 (Hopelessness) and CESD7 (Lack of hap-
piness). In the anxiety symptom network, the strongest 
associations were found between GAD1 (Nervousness or 
anxiety) and GAD2 (Uncontrollable worry), followed by 
GAD2 (Uncontrollable worry) and GAD3 (Generalized 
worry), as well as GAD4 (Trouble relaxing) and GAD5 
(Restlessness).
In the analysis of network centrality (results shown in 
Fig.  2 and Table  2), Strength measures the total direct 
connections of a node to other nodes, reflecting its over-
all importance within the network. GAD2 (Uncontrol-
lable worry) and GAD4 (Trouble relaxing) exhibited 
the highest strength centrality (1.126 and 1.106, respec-
tively), indicating these symptoms have the strongest 
direct associations with other symptoms and are likely 
core nodes in the anxiety symptom network. Other high-
strength nodes, such as GAD1 (Nervousness or anxiety) 
and GAD3 (Generalized worry), demonstrated extensive 
connectivity, further underscoring the central role of 
anxiety symptoms within the network. Betweenness cen-
trality, which quantifies a node’s role as a bridge within 
the shortest paths between other nodes, reflects its abil-
ity to regulate the flow of information. GAD1 (Nervous-
ness or anxiety) and GAD2 (Uncontrollable worry) had 
the highest betweenness values (52 and 46, respectively), 
highlighting their prominent roles as critical hub symp-
toms. CESD3 (Feeling depressed) also showed a relatively 
high betweenness value (36), suggesting its significant 
role in connecting depressive and anxiety symptom clus-
ters. The closeness centrality values for all nodes were 
relatively similar (approximately 0.003–0.004), indicat-
ing a uniformly connected network where symptoms are 
equidistant from each other, reflecting robust global con-
nectivity within the network.
In the analysis of weighted measures (results shown 
in Table  2), Barrat’s Strength, which incorporates edge 
weights to assess the total connectivity of a node, pro-
vides a more nuanced understanding of symptom 
importance. Consistent with the Strength findings, 
GAD2 (Uncontrollable worry) and GAD4 (Trouble 
relaxing) had the highest Barrat’s Strength values, fur-
ther supporting their roles as central nodes in the anxi-
ety network. Additionally, CESD3 (Feeling depressed) 
displayed a high weighted strength (1.023), highlighting 
its influence within the depression symptom network. 
Onnela’s Weighted Measure, which integrates both local 
Table 1  Basic information of depression-anxiety symptom 
network nodes among older adults living alone
Note: SD standard deviation, CESD-10 Center for Epidemiologic Studies 
Depression scale – 10, GAD-7 Generalized Anxiety Disorder 7-item scale
Label
Items
Mean
SD
Predictability(R2)
CESD1
Feeling bothered
0.34
0.64
0.396
CESD2
Trouble focus
0.64
0.82
0.199
CESD3
Feeling depressed
0.32
0.61
0.48
CESD4
Trouble doing anything
0.81
0.89
0.341
CESD5
Hopelessness
1.57
1.09
0.239
CESD6
Felt fearful
0.26
0.56
0.316
CESD7
Lack of happiness
1.81
1.17
0.231
CESD8
Loneliness
0.66
0.85
0.324
CESD9
Inability to get going
0.23
0.55
0.317
CESD10
Sleep quality
1.57
0.93
0.161
GAD1
Nervousness or anxiety
0.35
0.59
0.605
GAD2
Uncontrollable worry
0.25
0.54
0.701
GAD3
Generalized worry
0.29
0.58
0.662
GAD4
Trouble relaxing
0.21
0.50
0.669
GAD5
Restlessness
0.18
0.48
0.614
GAD6
Irritability
0.18
0.46
0.561
GAD7
Fear of horrible events
0.15
0.44
0.543

# Page 5

Page 5 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	
weighted connectivity and global network properties, 
was employed to evaluate node significance within the 
weighted network. GAD2 (Uncontrollable worry) and 
GAD4 (Trouble relaxing) again stood out with prominent 
values (0.794 and 0.758, respectively). Notably, GAD5 
(Restlessness) and CESD2 (Trouble focus) also exhibited 
relatively high Onnela values (0.903 and 0.904, respec-
tively), suggesting these symptoms may have localized 
importance and play key roles within specific substruc-
tures of the network.
Bridge symptoms analysis in the depression‑anxiety 
network
Bridge symptoms are those with the highest bridge 
strength centrality, representing the most influen-
tial symptoms within the network. Our analysis of 
bridge symptoms in the depression-anxiety network 
(see figure) revealed that GAD1(Nervousness or anxi-
ety, Bridge Expected Influence = 3.346) had the high-
est bridge strength, followed by GAD2(Uncontrollable 
worry, 
Bridge 
Expected 
Influence = 3.232), 
GAD3(Generalized worry, Bridge Expected Influ-
ence = 3.230), 
CESD3(Feeling 
depressed, 
Bridge 
Expected Influence = 3.094), and GAD4 (Trouble 
relaxing, Bridge Expected Influence = 3.036). These 
symptoms play a crucial role in linking depression and 
anxiety within the network (Fig. 3).
Gender differences in the depression‑anxiety network 
among elderly living alone
The depression-anxiety symptom networks for elderly 
individuals living alone, stratified by gender, are shown 
in Fig.  4. In the network for males (Table  3 and Sup-
plementary Fig. 1), the symptoms with the highest cen-
trality were CESD3 (Feeling depressed) and CESD4 
(Trouble doing anything) for depression, and GAD4 
(Trouble relaxing) and GAD2 (Uncontrollable worry) 
for anxiety. In the female network (Table  3 and Sup-
plementary Fig. 2), the symptoms with the highest cen-
trality for depression were CESD3 (Feeling depressed) 
and CESD8 (Loneliness), while for anxiety, the symp-
toms GAD2 (Uncontrollable worry) and GAD4 (Trou-
ble relaxing) had the highest centrality. The Network 
Comparison Test indicated a significant difference 
between the two network models (Test statistic M: 
0.243, P = 0.027), although no significant difference was 
found in strength centrality between the two networks 
(P = 0.716).
Fig. 1  Symptom network of depression and anxiety in older adults living alone. (Nodes: Represent symptoms of depression and anxiety. Edges: 
Indicate partial correlations between symptoms. Solid blue edges denote positive correlations, while dashed red edges indicate negative 
correlations. The thickness of the edges corresponds to the strength of the correlation.)

# Page 6

Page 6 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
Network stability and accuracy
We conducted stability analysis, accuracy assessment, 
and difference testing on the depression-anxiety symp-
tom network of elderly individuals living alone. The 
stability of centrality indices was evaluated (as shown 
in Fig.  5A), revealing correlation stability coefficients 
of 0.75, 0.672, and 0.128 for strength, closeness, and 
betweenness centrality, respectively. These results indi-
cate that the stability of strength and closeness centrality 
indices is relatively good, while the stability of between-
ness centrality is poor. The accuracy of edge weights in 
the symptom network was analyzed using bootstrap 
methods. The results presented in Fig. 5B show that the 
95% confidence intervals for edge weights are narrow, 
indicating accurate assessment of edge weights in this 
study. The results of strength and edge weight difference 
testing can be found in Supplementary Figs. 3–4.
Discussion
This study investigates the interrelationship between 
anxiety and depression symptoms among elderly indi-
viduals living alone in China through the lens of network 
Strength
Closeness
Betweenness
ExpectedInfluence
0.0
0.3
0.6
0.9
0.0000.0010.0020.0030.004 0
10
20
0.0
0.3
0.6
0.9
CESD1
CESD2
CESD3
CESD4
CESD5
CESD6
CESD7
CESD8
CESD9
CESD10
GAD1
GAD2
GAD3
GAD4
GAD5
GAD6
GAD7
Fig. 2  Centrality measures of depression and anxiety symptoms in older adults living alone

# Page 7

Page 7 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	
theory, thereby offering a novel theoretical framework 
for comprehending the complexities of mental health in 
older adults. To the best of our knowledge, this repre-
sents the first systematic inquiry focused on this specific 
demographic. Previous research has indicated that the 
core driving factors of comorbid depression and anxiety 
networks among disabled elderly individuals [37], those 
with hypertension [38], and those with diabetes [39] 
in China are primarily depression-related symptoms 
(CESD3:Feeling Depressed). Our research emphasizes 
the critical role of anxiety-related symptoms, particu-
larly GAD2 (Uncontrollable Worry) and GAD4 (Dif-
ficulty Relaxing), as core components of the symptom 
network. Their central position, both in terms of direct 
connectivity and weighted importance, indicates that 
these symptoms are integral to maintaining the anxiety-
depression network among elderly individuals living 
alone and can serve as primary targets for therapeutic 
interventions. Furthermore, the bridging role of CESD3 
(Feeling Depressed) highlights the interconnected nature 
of anxiety and depression, underscoring the importance 
of addressing the interactions between symptoms across 
disorders.
It has been reported that bridge symptoms may play 
a crucial role in the maintenance and progression of 
comorbid mental disorders and could be key targets for 
prevention and treatment [40].The study delineates piv-
otal bridging symptoms, including GAD1 (Nervous-
ness or anxiety), GAD2 (Uncontrollable worry), GAD3 
(Generalized worry), and CESD3 (Feeling depressed), 
which may form an interrelated core symptom cluster 
that collectively impacts the mental health and quality 
of life of elderly individuals residing alone. According to 
the DSM-5, GAD1 (Nervousness or anxiety) and GAD2 
(Uncontrollable worry) are prominent features of anxiety 
disorders [41]. Previous research also indicates that dur-
ing the COVID-19 pandemic, Uncontrollable worry was 
identified as a key symptom of anxiety and was closely 
associated with Nervousness or anxiety [42]. The role of 
Nervousness as a bridge symptom between anxiety and 
depression comorbidity has also been highlighted in 
studies on hypertensive elderly in China [43]. Research 
suggests that emotional support from other family mem-
bers or peers can alleviate anxiety among the elderly [38]. 
Due to a lack of interaction with their children, elderly 
individuals living alone are more likely to experience 
psychological changes such as worry and nervousness. 
Among the various depressive symptoms, CESD-3 (Feel-
ing depressed) emerged as a critical bridge symptom. 
Although the CESD scale is less commonly used in stud-
ies on anxiety and depression comorbidity, similar con-
clusions have been found in related research. The PHQ-9 
is a brief scale used to assess the severity of depression, 
consisting of nine items, each representing a depres-
sive symptom [44]. PHQ2 (Feeling down, depressed, or 
hopeless) is similar to CESD-3 (Feeling depressed) in 
its expression. Bian et al. found that PHQ2 was a bridge 
symptom in the network model of anxiety, depression, 
and personal control among elderly individuals living in 
the community [45]. These findings indicate that GAD1 
Table 2  Descriptive statistics of centrality indices
Note: The numbers in the table represent standardized Z values
Label
Items
Strength
Closeness
Betweenness
Barrat
Onnela
CESD1
Feeling bothered
0.82
0.004
12
0.82
0.782
CESD2
Trouble focus
0.551
0.003
0
0.551
0.904
CESD3
Feeling depressed
1.023
0.004
36
1.023
0.751
CESD4
Trouble doing anything
0.954
0.003
30
0.954
0.815
CESD5
Hopelessness
0.669
0.003
6
0.669
0.845
CESD6
Felt fearful
0.697
0.004
16
0.697
0.775
CESD7
Lack of happiness
0.646
0.003
16
0.646
0.766
CESD8
Loneliness
0.838
0.003
6
0.838
0.763
CESD9
Inability to get going
0.815
0.003
18
0.815
0.689
CESD10
Sleep quality
0.508
0.003
26
0.508
0.678
GAD1
Nervousness or anxiety
1.05
0.004
52
1.05
0.711
GAD2
Uncontrollable worry
1.126
0.004
46
1.126
0.794
GAD3
Generalized worry
1.075
0.004
2
1.075
0.696
GAD4
Trouble relaxing
1.106
0.003
30
1.106
0.758
GAD5
Restlessness
0.936
0.003
6
0.936
0.903
GAD6
Irritability
0.844
0.003
4
0.844
0.831
GAD7
Fear of horrible events
0.789
0.003
2
0.789
0.794

# Page 8

Page 8 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
(Nervousness or anxiety), GAD2 (Uncontrollable worry), 
and CESD-3 (Feeling depressed) may represent critical 
symptoms that contribute to the comorbidity of anxiety 
and depression among elderly individuals living indepen-
dently, thereby necessitating further investigation.
From a clinical practice perspective, this study provides 
significant insights for mental health interventions tar-
geting elderly individuals living alone in China. Interven-
tion strategies should prioritize GAD2 and GAD4, while 
also considering the bridging role of CESD3 to develop 
a multidimensional approach to symptom management. 
For instance, employing methods such as cognitive 
behavioral therapy could alleviate anxiety and depression 
[46–48], thereby enhancing emotional well-being and life 
satisfaction. Social support is instrumental in alleviating 
depressive and anxious symptoms among older adults 
[49, 50]. It is imperative to augment community engage-
ment initiatives for seniors living independently, thereby 
facilitating their social interactions and diminishing feel-
ings of isolation. Furthermore, it is crucial to consider 
gender differences, as this awareness can enhance com-
munity participation, expand mental health resources, 
Bridge Closeness
Bridge Expected Influence (1−step)
Bridge Strength
0.20 0.25 0.30 0.35 0.40 0.45
1.5
2.0
2.5
3.0
1.5
2.0
2.5
3.0
GAD7
GAD6
GAD5
GAD4
GAD3
GAD2
GAD1
CESD10
CESD9
CESD8
CESD7
CESD6
CESD5
CESD4
CESD3
CESD2
CESD1
Fig. 3  Bridge symptom analysis in the depression-anxiety network among elderly living alone

# Page 9

Page 9 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	
and reinforce policy support [51]. Ultimately, these initia-
tives aspire to improve mental health outcomes and over-
all quality of life for this vulnerable population.
Furthermore, when devising strategies, it is impera-
tive to take into account the cultural disparities between 
Chinese and Western populations. Considering the 
heightened dependence of elderly individuals in China 
on familial support, intervention strategies should prior-
itize the familial role while alleviating the adverse effects 
of social pressures on mental health, particularly con-
cerning living arrangements [52]. The government must 
enhance policy support for mental health by establishing 
psychological counseling services and promoting men-
tal health education to combat stigma. Future interven-
tions should embrace a holistic approach that integrates 
psychotherapy [53], pharmacotherapy [54], and social 
support [50], while also improving early screening mech-
anisms to avert the exacerbation of mental health issues 
among seniors living independently. In light of these con-
siderations, collaboration among government entities, 
community organizations, and families will be pivotal in 
enhancing the mental health of elderly individuals living 
alone, mitigating feelings of loneliness, and improving 
their overall quality of life.
Fig. 4  Depression-anxiety symptom networks in elderly individuals living alone by gender
Table 3  Standardized centrality indices by gender
Note: The numbers in the table represent standardized Z values
Label
Items
Male
Female
Strength
Closeness
Betweenness
Strength
Closeness
Betweenness
CESD1
Feeling bothered
0.845
0.004
30
0.797
0.004
12
CESD2
Trouble focus
0.466
0.003
0
0.519
0.003
0
CESD3
Feeling depressed
1.062
0.004
38
1.080
0.004
32
CESD4
Trouble doing anything
1.028
0.004
42
0.861
0.003
18
CESD5
Hopelessness
0.673
0.003
14
0.630
0.003
4
CESD6
Felt fearful
0.720
0.003
4
0.713
0.004
14
CESD7
Lack of happiness
0.621
0.003
16
0.616
0.003
4
CESD8
Loneliness
0.795
0.004
4
0.870
0.004
12
CESD9
Inability to get going
0.717
0.004
22
0.805
0.004
30
CESD10
Sleep quality
0.525
0.004
28
0.470
0.004
22
GAD1
Nervousness or anxiety
0.959
0.004
56
1.060
0.004
34
GAD2
Uncontrollable worry
1.108
0.004
30
1.168
0.004
30
GAD3
Generalized worry
1.040
0.004
0
1.057
0.004
6
GAD4
Trouble relaxing
1.122
0.004
24
1.078
0.004
20
GAD5
Restlessness
0.933
0.003
12
0.943
0.004
6
GAD6
Irritability
0.943
0.004
24
0.885
0.004
20
GAD7
Fear of horrible events
0.770
0.003
4
0.872
0.003
6

# Page 10

Page 10 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
Despite the valuable insights provided by this study 
through network analysis, several limitations should be 
acknowledged. First, the sample is limited to Chinese 
elderly individuals living alone, which may limit the gen-
eralizability of the findings to other cultural contexts 
or age groups. Second, the data were collected in 2018, 
which may not fully reflect the current social environ-
ment or the evolving mental health status of elderly 
individuals living alone. Additionally, the cross-sectional 
design of this study limits the ability to infer causal rela-
tionships. Future research should consider longitudinal 
designs to explore the dynamic changes in symptom net-
works over time and the potential causal relationships. 
Lastly, this study relied on self-reported measures of 
depression and anxiety symptoms, which may be subject 
to recall bias and social desirability effects. Future stud-
ies could incorporate biomarkers or objective psycho-
logical assessments to provide a more comprehensive 
understanding.
Conclusions
In summary, This study highlights the critical features 
of anxiety and depression symptom networks in older 
adults living alone, identifying GAD2 (Uncontrollable 
worry) and GAD4 (Trouble relaxing) as the core symp-
toms. Targeted interventions focusing on these central 
nodes may effectively disrupt the symptom network’s 
vicious cycles and alleviate the overall symptom bur-
den in this population. Future research should validate 
these findings in clinical settings to support precision 
treatment for anxiety and depression in older adults liv-
ing alone.
Supplementary Information
The online version contains supplementary material available at https://​doi.​
org/​10.​1186/​s12888-​024-​06443-2.
Supplementary Material 1
Acknowledgements
Not applicable.
Authors’ contributions
Yunling Zhang and Lina Miao conceived and designed the research. Ze Chang 
and Yunfan Zhang performed the research and revised the manuscript. Xiao 
Liang, Yunmeng Chen, Chunyan Guo, Xiansu Chi, Liuding Wang, Xie Wang, 
Hong Chen, Longtao Liu, and Zixuan Zhang analyzed the data and draw 
figures.
Funding
This research was supported and funded by the Scientific and Technological 
Innovation Project of CACMS(No. CI2021B006), CACMS Innovation Fund (No. 
CI2021A01301, CI2021A01311), Hospital capability enhancement project 
of Xiyuan Hospital, CACMS (No. XYZX0204-05, XYZX0101-21), the Innova-
tion Team and Talents Cultivation Program of National Administration of 
Traditional Chinese Medicine (No. ZYYCXTD-C-202007), the China Postdoctoral 
Researchers National Funding Program Project (GZC20233131), the National 
TCM Leading Personnel Support Program (NATCM Personnel and Education 
Department (2018) (No. 12).
Data availability
The data for this study were sourced from the Chinese Longitudinal Healthy 
Longevity Survey and Family Happiness (CLHLS-HF), conducted by the Peking 
University Research Center for Healthy Aging and Development. We have also 
obtained authorization to use this data for our research.
Fig. 5  A Stability analysis of the depression-anxiety symptom network in elderly individuals living alone. B Accuracy analysis of the edge weights 
in the depression-anxiety symptom network for elderly individuals living alone (Black lines represent the bootstrapped mean edge weights, 
while red lines represent the edge weights in the study sample)

# Page 11

Page 11 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	
Declarations
Ethics approval and consent to participate
The CLHLS study received ethical approval from the Peking University Institu-
tional Review Board (IRB00001052-13074), and written informed consent was 
obtained from each participant or their authorized representative. Participa-
tion in the CLHLS is voluntary, and respondents are free to withdraw from the 
study at any time without any consequences.
Consent for publication
Not applicable.
Competing interests
The authors declare no competing interests.
Author details
1 Xiyuan Hospital of China Academy of Traditional Chinese Medicine, Bei-
jing 100091, China. 2 The First Affiliated Hospital of Anhui, University of Tradi-
tional Chinese Medicine, Hefei 230031, China. 
Received: 1 September 2024   Accepted: 23 December 2024
References
	1.	
Tang T, Jiang J, Tang X. Prevalence of depressive symptoms among older 
adults in mainland China: A systematic review and meta-analysis. J Affect 
Disord. 2021;293:379–90.
	2.	
Huang X, Liu J, Bo A. Living arrangements and quality of life among 
older adults in China: does social cohesion matter? Aging Ment Health. 
2020;24(12):2053–62.
	3.	
Lim YM, Baek J, Lee S, Kim JS. Association between loneliness and depres-
sion among community-dwelling older women living alone in South 
Korea: the mediating effects of subjective physical health, resilience, and 
social support. Int J Environ Res Public Health. 2022;19(15):9246.
	4.	
Struzik M, Wilczynski KM, Chalubinski J, Mazgaj E, Krysta K. Comorbidity 
of substance use and mental disorders. Psychiatr Danub. 2017;29(Suppl 
3):623–8.
	5.	
Wang J, Chen T, Han B. Does co-residence with adult children associate 
with better psychological well-being among the oldest old in China? 
Aging Ment Health. 2014;18(2):232–9.
	6.	
O’Suilleabhain PS, Gallagher S, Steptoe A. Loneliness, living alone, and all-
cause mortality: the role of emotional and social loneliness in the elderly 
during 19 years of follow-up. Psychosom Med. 2019;81(6):521–6.
	7.	
TabueTeguo M, Simo-Tabue N, Stoykova R, Meillon C, Cogne M, Amiéva H, 
Dartigues JF. Feelings of loneliness and living alone as predictors of mor-
tality in the elderly: the PAQUID study. Psychosom Med. 2016;78(8):904–9.
	8.	
Hu C, Dai Z, Liu H, Liu S, Du M, Liu T, Yuan L. Decomposition and com-
parative analysis of depressive symptoms between older adults living 
alone and with others in China. Front Public Health. 2023;11:1265834.
	9.	
You H, Wang Y, Xiao LD, Liu L. Prevalence of and factors associated with 
negative psychological symptoms among elderly widows living alone in 
a Chinese remote sample: a cross-sectional study. Int J Environ Res Public 
Health. 2022;20(1):264.
	10.	 Fang H, Duan Y, Hou Y, Chang H, Hu S, Huang R. The association between 
living alone and depressive symptoms in older adults population: evi-
dence from the China Health and Retirement Longitudinal Study. Front 
Public Health. 2024;12:1441006.
	11.	 Zheng G, Zhou B, Fang Z, Jing C, Zhu S, Liu M, Chen X, Zuo L, Chen 
H, Hao G. Living alone and the risk of depressive symptoms: a cross-
sectional and cohort analysis based on the China Health and Retirement 
Longitudinal Study. BMC Psychiatry. 2023;23(1):853.
	12.	 Robb CE, de Jager CA, Ahmadi-Abhari S, Giannakopoulou P, Udeh-
Momoh C, McKeand J, Price G, Car J, Majeed A, Ward H, et al. Associations 
of social isolation with anxiety and depression during the early COVID-19 
pandemic: a survey of older adults in London, UK. Front Psychiatry. 
2020;11:591120.
	13.	 Yu J, Choe K, Kang Y. Anxiety of older persons living alone in the com-
munity. Healthcare (Basel) 2020;8(3).
	14.	 Ciuffreda G, Cabanillas-Barea S, Carrasco-Uribarren A, Albarova-Corral MI, 
Arguello-Espinosa MI, Marcen-Roman Y. Factors Associated with Depres-
sion and Anxiety in Adults ≥60 Years Old during the COVID-19 Pandemic: 
A Systematic Review. Int J Environ Res Public Health. 2021;18(22):11859.
	15.	 Daneshvari NO, Mojtabai R, Eaton WW, Cullen BA, Rodriguez KM, Spivak 
S. Symptom severity and care delay among patients with serious mental 
illness. J Health Care Poor Underserved. 2021;32(3):1312–9.
	16.	 Holt-Lunstad J, Smith TB, Baker M, Harris T, Stephenson D. Loneliness 
and social isolation as risk factors for mortality: a meta-analytic review. 
Perspect Psychol Sci. 2015;10(2):227–37.
	17.	 Borsboom D. A network theory of mental disorders. World Psychiatry. 
2017;16(1):5–13.
	18.	 McNally RJ. Can network analysis transform psychopathology? Behav Res 
Ther. 2016;86:95–104.
	19.	 Bringmann LF, Lemmens LH, Huibers MJ, Borsboom D, Tuerlinckx F. 
Revealing the dynamic network structure of the Beck Depression 
Inventory-II. Psychol Med. 2015;45(4):747–57.
	20.	 Fried EI, Epskamp S, Nesse RM, Tuerlinckx F, Borsboom D. What 
are’good’depression symptoms? Comparing the centrality of DSM and 
non-DSM symptoms of depression in a network analysis. J Affect Disord. 
2016;189:314–20.
	21.	 Hou B, Zhang H. Latent profile analysis of depression among older adults 
living alone in China. J Affect Disord. 2023;325:378–85.
	22.	 Baek J, Kim GU, Song K, Kim H. Decreasing patterns of depression in living 
alone across middle-aged and older men and women using a longitudi-
nal mixed-effects model. Soc Sci Med. 2023;317:115513.
	23.	 Choi HS, Lee JE. Factors affecting depression in middle-aged and elderly 
men living alone: a cross-sectional path analysis model. Am J Mens 
Health. 2022;16(1):15579883221078134.
	24.	 Chen Y. Risk factors for depression among older adults living alone in 
Shanghai, China. Psychogeriatrics. 2022;22(6):780–5.
	25.	 Zeng Y. Towards deeper research and better policy for healthy aging –
using the unique data of Chinese longitudinal healthy longevity survey. 
China Economic J. 2012;5(2–3):131–49.
	26.	 Chen Z-T, Wang X-M, Zhong Y-S, Zhong W-F, Song W-Q, Wu X-B. Associa-
tion of changes in waist circumference, waist-to-height ratio and weight-
adjusted-waist index with multimorbidity among older Chinese adults: 
results from the Chinese longitudinal healthy longevity survey (CLHLS). 
BMC Public Health. 2024;24(1):318.
	27.	 Radloff LS. The CES-D scale: a self-report depression scale for research in 
the general population. Appl Psychol Meas. 1977;1(3):385–401.
	28.	 Chen H, Mui AC. Factorial validity of the center for epidemiologic studies 
depression scale short form in older population in China. Int Psychogeri-
atr. 2014;26(1):49–57.
	29.	 Spitzer RL, Kroenke K, Williams JB, Lowe B. A brief measure for assess-
ing generalized anxiety disorder: the GAD-7. Arch Intern Med. 
2006;166(10):1092–7.
	30.	 Shih YC, Chou CC, Lu YJ, Yu HY. Reliability and validity of the traditional 
Chinese version of the GAD-7 in Taiwanese patients with epilepsy. J 
Formos Med Assoc. 2022;121(11):2324–30.
	31.	 Liu H, Yang X, Guo LL, Li JL, Xu G, Lei Y, Li X, Sun L, Yang L, Yuan T, et al. 
Frailty and incident depressive symptoms during short- and long-term 
follow-up period in the middle-aged and elderly: findings from the 
Chinese nationwide cohort study. Front Psychiatry. 2022;13:848849.
	32.	 Hao XY, Guo YX, Lou JS, Cao JB, Liu M, Mi TY, Li A, You SH, Cao FY, Liu YH, et al. 
Mental health changes in elderly patients undergoing non-cardiac surgery 
during the COVID-19 pandemic in China. J Affect Disord. 2023;343:77–85.
	33.	 Epskamp S, Waldorp LJ, Mottus R, Borsboom D. The Gaussian Graphical 
Model in Cross-Sectional and Time-Series Data. Multivariate Behav Res. 
2018;53(4):453–80.
	34	 Fruchterman TM, Reingold EM. Graph drawing by force-directed place-
ment. Softw Pract Exper. 1991;21(11):1129–64.
	35.	 Tibshirani R. Regression shrinkage and selection via the lasso. J R Stat Soc 
Ser B Stat Methodol. 1996;58(1):267–88.
	36.	 Zhang M, Zhang D, Wells MT. Variable selection for large p small n regres-
sion models with incomplete data: mapping QTL with epistases. BMC 
Bioinformatics. 2008;9:251.
	37.	 Zhang P, Wang L, Zhou Q, Dong X, Guo Y, Wang P, He W, Wang R, Wu T, 
Yao Z, et al. A network analysis of anxiety and depression symptoms in 
Chinese disabled elderly. J Affect Disord. 2023;333:535–42.

# Page 12

Page 12 of 12
Chang et al. BMC Psychiatry           (2025) 25:28 
	38.	 Ma H, Zhao M, Liu Y, Wei P. Network analysis of depression and anxiety 
symptoms and their associations with life satisfaction among Chinese 
hypertensive older adults: a cross-sectional study. Front Public Health. 
2024;12:1370359.
	39.	 Zhang Y, Cui Y, Li Y, Lu H, Huang H, Sui J, Guo Z, Miao D. Network analysis 
of depressive and anxiety symptoms in older Chinese adults with diabe-
tes mellitus. Front Psychiatry. 2024;15:1328857.
	40.	 Jones PJ, Ma R, McNally RJ. Bridge centrality: a network approach to 
understanding comorbidity. Multivariate Behav Res. 2021;56(2):353–67.
	41.	 Munir S, Takov V: Generalized Anxiety Disorder. In: StatPearls. edn. Treasure 
Island (FL) ineligible companies. Disclosure: Veronica Takov declares no 
relevant financial relationships with ineligible companies. StatPearls 
Publishing Copyright © 2024, StatPearls Publishing LLC. 2024.
	42.	 Zhang L, Tao Y, Hou W, Niu H, Ma Z, Zheng Z, Wang S, Zhang S, Lv Y, Li 
Q, et al. Seeking bridge symptoms of anxiety, depression, and sleep 
disturbance among the elderly during the lockdown of the COVID-19 
pandemic-A network approach. Front Psychiatry. 2022;13:919251.
	43.	 Byeon H. Exploring factors for predicting anxiety disorders of the elderly 
living alone in South Korea using interpretable machine learning: a 
population-based study. Int J Environ Res Public Health. 2021;18(14):7625.
	44.	 Kroenke K, Spitzer RL, Williams JB. The PHQ-9: validity of a brief depression 
severity measure. J Gen Intern Med. 2001;16(9):606–13.
	45.	 Bian Z, Xu R, Shang B, Lv F, Sun W, Li Q, Gong Y, Luo C. Associations 
between anxiety, depression, and personal mastery in community-
dwelling older adults: a network-based analysis. BMC Psychiatry. 
2024;24(1):192.
	46.	 McKelway M, Banerjee A, Grela E, Schilbach F, Sequeira M, Sharma G, 
Vaidyanathan G, Duflo E. Effects of cognitive behavioral therapy and cash 
transfers on older persons living alone in India : a randomized trial. Ann 
Intern Med. 2023;176(5):632–41.
	47.	 Garke MA, HentatiIsacsson N, Kolbeinsson O, Hesser H, Mansson 
KNT. Improvements in emotion regulation during cognitive behavior 
therapy predict subsequent social anxiety reductions. Cogn Behav Ther. 
2025;54(1):78–95.
	48.	 Laidlaw K, Davidson K, Toner H, Jackson G, Clark S, Law J, Howley M, 
Bowie G, Connery H, Cross S. A randomised controlled trial of cognitive 
behaviour therapy vs treatment as usual in the treatment of mild to 
moderate late life depression. Int J Geriatr Psychiatry. 2008;23(8):843–50.
	49.	 Gautam S, Poudel A, Khatry RA, Mishra R. The mediating role of perceived 
social support on loneliness and depression in community-dwelling 
Nepalese older adults. BMC Geriatr. 2024;24(1):854.
	50.	 Liu X, Li C, Chen X, Tian F, Liu J, Liu Y, Liu X, Yin X, Wu X, Zuo C, et al. Social 
support and sleep quality in people with schizophrenia living in the com-
munity: the mediating roles of anxiety and depression symptoms. Front 
Public Health. 2024;12:1414868.
	51.	 Mayerl H, Schultz A, Freidl W, Stolz E. Short-term dynamics of loneliness 
and depressive symptoms: Gender differences in older adults. Arch 
Gerontol Geriatr. 2024;123:105423.
	52.	 Gao Q, Lei C, Wei X, Peng L, Wang X, Yue A, Shi Y. Exploring the interplay 
of living arrangements, social support, and depression among older 
adults in rural northwest China. BMC Public Health. 2024;24(1):3297.
	53.	 Steare T, Buckman JEJ, Stott J, John A, Singh S, Wheatley J, Pilling S, 
Saunders R. Bidirectional changes in depressive symptoms and social 
functioning in older adults attending psychological therapy services. J 
Affect Disord. 2025;369:954–62.
	54.	 Ishtiak-Ahmed K, Christensen KS, Mortensen EL, Nierenberg AA, Gasse 
C. Sociodemographics and clinical factors associated with depression 
treatment outcomes in 65,741 first-time users of selective serotonin 
reuptake inhibitors: A Danish cohort study in older adults. J Affect Disord. 
2024;367:244–54.
Publisher’s Note
Springer Nature remains neutral with regard to jurisdictional claims in pub-
lished maps and institutional affiliations.
