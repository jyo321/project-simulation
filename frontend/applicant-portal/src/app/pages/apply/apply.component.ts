import { NgIf } from '@angular/common';
import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { switchMap } from 'rxjs/operators';
import { ApplicationsService } from '../../services/applications.service';

@Component({
  selector: 'app-apply',
  standalone: true,
  imports: [FormsModule, NgIf],
  template: `
    <div class="page">
      <div class="page-header">
        <h1>Apply for a loan</h1>
        <p class="page-subtitle">Tell us a bit about yourself and how much you're looking to borrow — it takes about a minute.</p>
      </div>

      <p *ngIf="error" class="alert alert-error">{{ error }}</p>

      <form (ngSubmit)="submit()">
        <div class="field-row">
          <label>First name<input name="firstName" [(ngModel)]="firstName" required /></label>
          <label>Last name<input name="lastName" [(ngModel)]="lastName" required /></label>
        </div>
        <div class="field-row">
          <label>Email<input name="email" type="email" [(ngModel)]="email" required /></label>
          <label>Phone<input name="phone" [(ngModel)]="phone" required /></label>
        </div>
        <div class="field-row">
          <label>Requested amount (USD)<input name="amount" type="number" min="0" [(ngModel)]="requestedAmount" required /></label>
          <label>
            Purpose
            <select name="purpose" [(ngModel)]="purpose" required>
              <option value="Home Improvement">Home Improvement</option>
              <option value="Debt Consolidation">Debt Consolidation</option>
              <option value="Auto">Auto</option>
              <option value="Other">Other</option>
            </select>
          </label>
        </div>
        <button type="submit" [disabled]="submitting">
          <span class="spinner" *ngIf="submitting"></span>{{ submitting ? 'Submitting…' : 'Submit application' }}
        </button>
      </form>
    </div>
  `,
})
export class ApplyComponent {
  firstName = '';
  lastName = '';
  email = '';
  phone = '';
  requestedAmount = 10000;
  purpose = 'Home Improvement';
  submitting = false;
  error = '';

  constructor(
    private readonly applications: ApplicationsService,
    private readonly router: Router,
  ) {}

  submit(): void {
    this.submitting = true;
    this.error = '';

    this.applications
      .createApplicant({ firstName: this.firstName, lastName: this.lastName, email: this.email, phone: this.phone })
      .pipe(
        switchMap((applicant) =>
          this.applications.createApplication({
            applicantId: applicant.id,
            requestedAmount: this.requestedAmount,
            purpose: this.purpose,
          }),
        ),
      )
      .subscribe({
        next: (application) => this.router.navigate(['/applications', application.id, 'documents']),
        error: (err) => {
          this.submitting = false;
          this.error = 'Could not submit your application. Please try again.';
          console.error(err);
        },
      });
  }
}
