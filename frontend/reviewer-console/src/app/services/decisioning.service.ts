import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';

export interface ReviewerQueueItem {
  loanApplicationId: string;
  applicantId: string;
  applicantName: string;
  requestedAmount: number;
  purpose: string;
  status: string;
  riskScore: number | null;
  fraudFlagged: boolean;
  submittedAt: string | null;
}

@Injectable({ providedIn: 'root' })
export class DecisioningService {
  private readonly baseUrl = environment.decisioningApiBaseUrl;

  constructor(private readonly http: HttpClient) {}

  getQueue(): Observable<ReviewerQueueItem[]> {
    return this.http.get<ReviewerQueueItem[]>(`${this.baseUrl}/reviewer-queue`);
  }

  decide(loanApplicationId: string, reviewerId: string, outcome: 'Approved' | 'Rejected', reason: string): Observable<unknown> {
    return this.http.post(`${this.baseUrl}/applications/${loanApplicationId}/decision`, { reviewerId, outcome, reason });
  }
}
