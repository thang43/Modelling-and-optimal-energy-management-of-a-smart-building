clc;
clear;
close all;

%% parameters
PV_cap = 100; %PV power capacity in MW
P_BESS = 50; %BESS power capacity in MW
E_BESS = 200; %BESS energy capacity in MWh

rate_sd = 0.005; %hourly self-discharge rate
eta_ch = 0.98; %charging efficiency
eta_dis = 0.98; %discharging efficiency

P_BESS_min = 0; %BESS minimum charging/discharing power in MW;
SOC_min = 0.1; %lower limit for SOC
SOC_max = 1; %upper limit for SOC
P_gen_min = 0; %lower limit for hybrid power generation
P_gen_max = 100; %upper limit for hybrid power generation

SOC_0 = 0.12; %inital SOC for a daily operation
tau = 1; %time length, 1 hour

%% inputs
price = [
    60;55;50;45;50;58;
    75;150;120;100;95;90;
    90;85;90;105;130;150
    200;120;90;80;70;65
    ]; %$/MWh for both buying and selling prices

PV_gen = [ 0;0;0;0;0;0;
    0.05;0.23;0.43;0.64;0.68;0.89;
    0.98;0.95;0.70;0.42;0.25;0.20;
    0.08;0.01;0;0;0;0
    ]; % percentage to the power capacity

%% variables
P_gen = sdpvar(24,1);
bet_ch = binvar(24,1);
bet_dis = binvar(24,1);
P_ch = sdpvar(24,1);
P_dis = sdpvar(24,1);
E = sdpvar(24,1);
SOC = sdpvar(24,1);

%% objective function
obj = -price'*P_gen*tau; % maximise generation revenue

%% daily operation constraints
cons = [];
for h=1:24
    cons = [cons,P_gen_min<=P_gen(h)<=P_gen_max];
    cons = [cons,bet_ch(h)+bet_dis(h)<=1];
    cons = [cons,bet_ch(h)*P_BESS_min<=P_ch(h)<=bet_ch(h)*P_BESS];
    cons = [cons,bet_dis(h)*P_BESS_min<=P_dis(h)<=bet_dis(h)*P_BESS];

    %% please add constraints for energy calculation, SOC calculation and SOC limits:

    if h==1
    cons = [cons,E(h)==SOC_0*E_BESS*(1-rate_sd)+P_ch(h)*eta_ch - P_dis(h)/eta_dis];
    else
    cons = [cons,E(h)==      E(h-1)*(1-rate_sd)+P_ch(h)*eta_ch - P_dis(h)/eta_dis];
    end
    cons = [cons, SOC(h) == E(h) / E_BESS];
    cons = [cons, SOC_min <= SOC(h) <= SOC_max];
    cons = [cons,P_gen(h)==PV_gen(h)*PV_cap+P_dis(h)-P_ch(h)];
end
cons = [cons,SOC(24)==SOC_0];

%% optimisation
option = sdpsettings('solver','BNB');
sol = optimize(cons, obj, option)

%% results
Res_P_gen = value(P_gen);
Res_SOC = value(SOC);

%% plots
figure
plot(Res_P_gen, 'b','linewidth',1);
xlabel('Time (hour)')
xticks([1,6,12,18,24])
xticklabels([1,6,12,18,24])
ylabel('Energy Transaction (MWh)')

figure
bar(Res_SOC);
xlabel('Time (hour)')
xticks([1,6,12,18,24])
xticklabels([1,6,12,18,24])
ylabel('SOC (%)')
