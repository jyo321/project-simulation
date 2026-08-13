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
      <h1>Apply for a loan</h1>
      <form (ngSubmit)="submit()">
        <label>First name<input name="firstName" [(ngModel)]="firstName" required /></label>
        <label>Last name<input name="lastName" [(ngModel)]="lastName" required /></label>
        <label>Email<input name="email" type="email" [(ngModel)]="email" required /></label>
        <label>Phone<input name="phone" [(ngModel)]="phone" required /></label>
        <label>Requested amount (USD)<input name="amount" type="number" [(ngModel)]="requestedAmount" required /></label>
        <label>Purpose
          <select name="purpose" [(ngModel)]="purpose" required>
            <option value="Home Improvement">Home Improvement</option>
            <option value="Debt Consolidation">Debt Consolidation</option>
            <option value="Auto">Auto</option>
            <option value="Other">Other</option>
          </select>
        </label>
        <button type="submit" [disabled]="submitting">{{ submitting ? 'Submitting…' : 'Submit application' }}</button>
      </form>
      <p *ngIf="error" style="color: #b00020">{{ error }}</p>
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
