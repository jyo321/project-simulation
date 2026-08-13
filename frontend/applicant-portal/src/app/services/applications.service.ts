import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';

export interface Applicant {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
}

export interface LoanApplication {
  id: string;
  applicantId: string;
  requestedAmount: number;
  purpose: string;
  status: string;
  riskScore: number | null;
  createdAt: string;
  submittedAt: string | null;
  decidedAt: string | null;
}

@Injectable({ providedIn: 'root' })
export class ApplicationsService {
  private readonly baseUrl = environment.applicationsApiBaseUrl;

  constructor(private readonly http: HttpClient) {}

  createApplicant(request: { firstName: string; lastName: string; email: string; phone: string }): Observable<Applicant> {
    return this.http.post<Applicant>(`${this.baseUrl}/applicants`, request);
  }

  createApplication(request: { applicantId: string; requestedAmount: number; purpose: string }): Observable<LoanApplication> {
    return this.http.post<LoanApplication>(`${this.baseUrl}/applications`, request);
  }

  /** Submits the application — this is what enqueues the fire-and-forget credit scoring job server-side. */
  submitApplication(id: string): Observable<unknown> {
    return this.http.post(`${this.baseUrl}/applications/${id}/submit`, {});
  }

  getApplication(id: string): Observable<LoanApplication> {
    return this.http.get<LoanApplication>(`${this.baseUrl}/applications/${id}`);
  }
}
